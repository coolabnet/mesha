#!/usr/bin/env python3
"""Unit tests for adapters/mesh/normalize.py"""

import sys
import unittest
from pathlib import Path

# Add adapters/mesh to path so we can import normalize
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "adapters" / "mesh"))

from normalize import (  # noqa: E402
    FIELD_MAP,
    INVENTORY_FIELDS,
    SEVERITY_MAP,
    _clean_mac,
    compute_drift,
    find_inventory_node,
    normalize_node,
)


class TestNormalizeNode(unittest.TestCase):
    def test_basic_field_remapping(self):
        raw = {"hostname": "test-node", "firmware_version": "1.0", "status": "online"}
        result = normalize_node(raw)
        self.assertEqual(result["hostname"], "test-node")
        self.assertEqual(result["firmware_version"], "1.0")
        self.assertEqual(result["status"], "online")

    def test_status_normalization_online(self):
        for val in ["true", "1", "up", "reachable", "online", "running", True, 1]:
            result = normalize_node({"status": val})
            self.assertEqual(result["status"], "online", f"Failed for input: {val!r}")

    def test_status_normalization_offline(self):
        for val in ["false", "0", "down", "unreachable", "offline", False, 0]:
            result = normalize_node({"status": val})
            self.assertEqual(result["status"], "offline", f"Failed for input: {val!r}")

    def test_status_passthrough(self):
        for val in ["degraded", "unknown"]:
            result = normalize_node({"status": val})
            self.assertEqual(result["status"], val)

    def test_internal_fields_stripped(self):
        raw = {
            "hostname": "test",
            "error": "some error",
            "collected_at": "2026-01-01",
            "node_ip": "10.0.0.1",
            "interfaces": [],
            "radios": [],
            "mesh_neighbors": [],
            "uptime_human": "2 days",
        }
        result = normalize_node(raw)
        self.assertNotIn("error", result)
        self.assertNotIn("collected_at", result)
        self.assertNotIn("node_ip", result)
        self.assertNotIn("interfaces", result)
        self.assertNotIn("radios", result)
        self.assertNotIn("mesh_neighbors", result)
        self.assertNotIn("uptime_human", result)

    def test_field_map_remapping(self):
        # system_hostname should map to hostname
        raw = {"system_hostname": "my-node"}
        result = normalize_node(raw)
        self.assertEqual(result["hostname"], "my-node")


class TestCleanMac(unittest.TestCase):
    def test_colon_separated(self):
        self.assertEqual(_clean_mac("AA:BB:CC:DD:EE:FF"), "aabbccddeeff")

    def test_hyphen_separated(self):
        self.assertEqual(_clean_mac("aa-bb-cc-dd-ee-ff"), "aabbccddeeff")

    def test_dot_separated(self):
        self.assertEqual(_clean_mac("aabb.ccdd.eeff"), "aabbccddeeff")

    def test_no_separator(self):
        self.assertEqual(_clean_mac("AABBCCDDEEFF"), "aabbccddeeff")

    def test_empty(self):
        self.assertEqual(_clean_mac(""), "")

    def test_non_string(self):
        # str(None) -> "none", then non-hex chars (n, o) are stripped, leaving "e"
        self.assertEqual(_clean_mac(None), "e")


class TestFindInventoryNode(unittest.TestCase):
    def setUp(self):
        self.inventory = [
            {"hostname": "porao", "mac": "d8:b3:70:c0:7c:92", "name": "Porão"},
            {"hostname": "yuri", "mac": "f4:e2:c6:83:01:e0", "name": "Yuri"},
        ]

    def test_match_by_hostname(self):
        live = {"hostname": "porao", "mac": ""}
        result = find_inventory_node(live, self.inventory)
        self.assertIsNotNone(result)
        self.assertEqual(result["hostname"], "porao")

    def test_match_by_mac(self):
        live = {"hostname": "", "mac": "f4:e2:c6:83:01:e0"}
        result = find_inventory_node(live, self.inventory)
        self.assertIsNotNone(result)
        self.assertEqual(result["hostname"], "yuri")

    def test_match_by_mac_different_format(self):
        live = {"hostname": "", "mac": "F4-E2-C6-83-01-E0"}
        result = find_inventory_node(live, self.inventory)
        self.assertIsNotNone(result)
        self.assertEqual(result["hostname"], "yuri")

    def test_no_match(self):
        live = {"hostname": "unknown", "mac": "00:00:00:00:00:00"}
        result = find_inventory_node(live, self.inventory)
        self.assertIsNone(result)


class TestComputeDrift(unittest.TestCase):
    def test_no_drift(self):
        live = {
            "hostname": "porao",
            "mac": "d8:b3:70:c0:7c:92",
            "role": "leaf",
            "status": "online",
            "site": "Site A",
            "model": "Model X",
            "firmware_version": "1.0",
        }
        inv = {
            "hostname": "porao",
            "mac": "d8:b3:70:c0:7c:92",
            "role": "leaf",
            "status": "online",
            "site": "Site A",
            "model": "Model X",
            "firmware_version": "1.0",
        }
        drift = compute_drift(live, inv)
        self.assertEqual(drift, [])

    def test_drift_detected(self):
        live = {
            "hostname": "porao",
            "mac": "d8:b3:70:c0:7c:92",
            "role": "leaf",
            "status": "offline",
            "site": "Site A",
            "model": "Model X",
            "firmware_version": "1.0",
        }
        inv = {
            "hostname": "porao",
            "mac": "d8:b3:70:c0:7c:92",
            "role": "leaf",
            "status": "online",
            "site": "Site A",
            "model": "Model X",
            "firmware_version": "1.0",
        }
        drift = compute_drift(live, inv)
        self.assertTrue(len(drift) > 0)
        fields = [d["field"] for d in drift]
        self.assertIn("status", fields)

    def test_drift_severity(self):
        live = {
            "hostname": "porao",
            "mac": "aa:bb:cc:dd:ee:ff",
            "role": "leaf",
            "status": "online",
            "site": "Site A",
            "model": "Model X",
            "firmware_version": "1.0",
        }
        inv = {
            "hostname": "porao",
            "mac": "d8:b3:70:c0:7c:92",
            "role": "leaf",
            "status": "online",
            "site": "Site A",
            "model": "Model X",
            "firmware_version": "1.0",
        }
        drift = compute_drift(live, inv)
        mac_drift = [d for d in drift if d["field"] == "mac"]
        self.assertTrue(len(mac_drift) > 0)
        self.assertEqual(mac_drift[0]["severity"], "error")  # mac is severity "error"

    def test_both_none_no_drift(self):
        live = {"hostname": "porao"}
        inv = {"hostname": "porao"}
        drift = compute_drift(live, inv)
        self.assertEqual(drift, [])


class TestFieldMap(unittest.TestCase):
    def test_field_map_not_empty(self):
        self.assertTrue(len(FIELD_MAP) > 0)

    def test_severity_map_not_empty(self):
        self.assertTrue(len(SEVERITY_MAP) > 0)

    def test_inventory_fields_defined(self):
        expected = {"name", "hostname", "mac", "site", "model", "firmware_version", "role", "status", "notes"}
        self.assertEqual(INVENTORY_FIELDS, expected)


if __name__ == "__main__":
    unittest.main()
