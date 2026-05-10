# Comprehensive Strategy for Automating LibreMesh Testing with Virtual QEMU Nodes

## Executive Summary

This document outlines a comprehensive strategy for implementing automated testing of the LibreMesh framework using virtual nodes in QEMU. The strategy leverages existing research and development work, particularly the GSoC 2025 project that added Wi-Fi support to QEMU simulations, to create a robust, automated testing framework suitable for continuous integration environments.

## Research Findings

### 1. Core Virtualization Infrastructure

The LibreMesh project already provides foundational support for running in QEMU through:

- **VIRTUALIZING.md** documentation in the lime-packages repository
- Pre-built images available from LibreRouterOS releases
- Requirements: generic-rootfs.tar.gz and generic-kernel.bin generated from x86 build target

**Limitations Identified**:

- ICMPv4 communication doesn't work between QEMU nodes (workaround: use IPv6/ping6)
- No native Wi-Fi support in base images
- Most other functionality (initialization scripts, services) works as expected

### 2. Wi-Fi Enhancement Work (GSoC 2025)

The Google Summer of Code 2025 project successfully added Wi-Fi capabilities by:

- Integrating the **mac80211_hwsim** kernel module for software-based Wi-Fi simulation
- Creating patches to address Wi-Fi band configuration issues, particularly for 802.11ax
- Demonstrating AP-STA communication within single virtual machines
- Integrating with **vwifi** project to enable inter-VM Wi-Fi communication

### 3. Automation Infrastructure Planning

GitHub issue #1178 provides a structured approach to implementation:

- Review of existing tools (mac80211_hwsim, vwifi, OpenWrt test frameworks)
- Development of QEMU instances with WiFi capabilities
- Creation of mesh networks with multiple Wi-Fi capable nodes
- Script development using rpcd interfaces for network diagnostics
- Automation scripts for WiFi-capable QEMU instances
- Integration with existing LibreMesh testing framework
- Documentation and final testing phases

## Implementation Strategy

### Phase 1: Foundation Establishment (Weeks 1-2)

**Objective**: Establish reliable single-node QEMU testing capability

**Activities**:

1. Environment Setup
   - Install required packages: qemu-system-x86, dnsmasq, iptables, build-essential
   - Set up LibreMesh build environment with necessary dependencies
   - Configure kernel module support for mac80211_hwsim

2. Base Image Validation
   - Build LibreMesh targeting x86 architecture with ramfs.bzImage option
   - Generate or obtain generic-rootfs.tar.gz and generic-kernel.bin
   - Validate basic VM functionality (boot process, service initialization)

3. Network Configuration
   - Set up host-only networking for VM communication
   - Configure DHCP and DNS services via dnsmasq
   - Test basic connectivity between host and VM

### Phase 2: Wireless Capability Integration (Weeks 3-4)

**Objective**: Add Wi-Fi simulation capabilities to virtual nodes

**Activities**:

1. Kernel Module Integration
   - Add kmod-mac80211-hwsim to LibreMesh package selection
   - Patch Wi-Fi configuration issues identified in GSoC work
   - Build Wi-Fi enabled firmware images

2. Single-Mode Wi-Fi Testing
   - Validate Wi-Fi interface detection in VM
   - Test basic Wi-Fi functionality (scan, association)
   - Verify mac80211_hwsim module operation

3. Inter-VM Wi-Fi Communication
   - Integrate vwifi framework or equivalent solution
   - Establish communication channels between VM Wi-Fi interfaces
   - Test frame relay mechanism across virtual machines

### Phase 3: Mesh Network Formation (Weeks 5-6)

**Objective**: Create multi-node mesh networks for realistic testing

**Activities**:

1. Topology Design
   - Define network topologies (line, star, mesh, tree)
   - Create scalable VM provisioning scripts
   - Implement role-based configuration (gateway, client, repeater)

2. Configuration Automation
   - Develop scripts for automatic VM provisioning
   - Create templates for different node roles
   - Implement network parameterization (SSID, channels, security)

3. Mesh Protocol Validation
   - Test B.A.T.M.A.N. advanced, BMX6/7, or other routing protocols
   - Validate mesh formation and convergence times
   - Test traffic routing and load balancing characteristics

### Phase 4: Automation Framework Development (Weeks 7-9)

**Objective**: Build reusable testing automation components

**Activities**:

1. Lifecycle Management
   - Create scripts for VM provisioning, starting, stopping, and cleanup
   - Implement snapshot/restore capabilities for test consistency
   - Develop resource management to prevent resource exhaustion

2. Test Orchestration
   - Design test case definition format (YAML/JSON)
   - Implement test sequence orchestration engine
   - Create result collection and reporting mechanisms

3. Diagnostic Integration
   - Develop rpcd-based remote execution framework
   - Create standardized test probes and measurement tools
   - Implement logging and trace collection mechanisms

### Phase 5: CI/CD Integration (Weeks 10-12)

**Objective**: Integrate testing framework with continuous integration

**Activities**:

1. Pipeline Integration
   - Create CI job definitions for popular platforms (GitHub Actions, GitLab CI)
   - Implement gating checks for pull requests
   - Establish nightly/build trigger mechanisms

2. Resource Management
   - Implement concurrent test execution limits
   - Create resource pooling for VM instances
   - Develop cleanup procedures for failed/incomplete tests

3. Reporting and Metrics
   - Establish standardized test result formats
   - Create trend analysis and regression detection
   - Implement notification systems for test failures

## Technical Implementation Details

### Required Software Components

- **QEMU**: System emulator for x86 architecture
- **Linux Kernel**: With mac80211_hwsim module support
- **LibreMesh**: Custom-built firmware with Wi-Fi capabilities
- **vwifi** or equivalent: For inter-VM Wi-Fi frame relay
- **dnsmasq**: DHCP and DNS services for network management
- **iptables**: Network traffic shaping and filtering

### Key Configuration Considerations

#### Network Architecture

```text
Host Machine
├── dnsmasq (DHCP/DNS)
├── vwifi-server (Wi-Fi frame relay)
├── Tap interfaces (VM network connections)
└── Virtual Switches (for inter-VM communication)

Guest VMs (LibreMesh Instances)
├── VirtIO network interfaces (to host)
├── Wireless interfaces (mac80211_hwsim)
├── Virtual Wi-Fi connections (via vwifi)
└── LibreMesh services (olsrd, bmx6, etc.)
```

#### Performance Optimization

- Use VirtIO drivers for improved network performance
- Allocate adequate RAM/CPU resources based on test density
- Consider using QEMU snapshots for rapid environment reset
- Implement thoughtful CPU pinning for consistent performance

### Testing Methodology

#### Test Categories

1. **Bootstrap Tests**: Verify VM startup and basic service initialization
2. **Network Tests**: Validate connectivity, routing, and mesh formation
3. **Service Tests**: Check specific LibreMesh services (lime-config, rpcd, etc.)
4. **Protocol Tests**: Validate routing protocol behavior and convergence
5. **Stress Tests**: Evaluate performance under various load conditions
6. **Failure Tests**: Assess resilience to network partitions and node failures

#### Automation Approach

- Use declarative test definitions for reproducibility
- Implement parameterized testing for configuration variations
- Develop reusable test components for common operations
- Create comprehensive setup/teardown procedures

## Risk Assessment and Mitigation

### Technical Risks

1. **Performance Limitations**: Virtualization overhead affecting test validity
   - Mitigation: Calibrate tests against known hardware baselines
   - Mitigation: Focus on functional correctness over absolute performance

2. **Wi-Fi Simulation Fidelity**: Differences between simulated and real Wi-Fi
   - Mitigation: Document limitations and appropriate use cases
   - Mitigation: Validate critical behaviors with periodic hardware testing

3. **Resource Exhaustion**: Concurrent tests consuming excessive resources
   - Mitigation: Implement strict resource quotas and cleanup procedures
   - Mitigation: Use containerization or lightweight VMs where appropriate

### Operational Risks

1. **Maintenance Burden**: Complex framework requiring ongoing maintenance
   - Mitigation: Design for modularity and reuse
   - Mitigation: Create comprehensive documentation and training materials

2. **Integration Complexity**: Difficulty integrating with existing workflows
   - Mitigation: Provide clear migration paths and compatibility layers
   - Mitigation: Start with non-critical paths and expand gradually

## Success Criteria

### Short-Term (3 Months)

- Reliable single-node VM boot and basic functionality testing
- Working Wi-Fi simulation between two virtual nodes
- Basic automation scripts for common test scenarios
- Integration with at least one CI platform

### Medium-Term (6 Months)

- Multi-node mesh network formation and testing capability
- Comprehensive test suite covering core LibreMesh functionality
- Regular automated testing in development workflow
- Documented procedures and troubleshooting guides

### Long-Term (12 Months)

- Full test automation replacing majority of manual testing
- Integration with project release processes
- Community adoption and contribution to testing framework
- Continuous improvement based on usage feedback

## Resource Requirements

### Personnel

- 1-2 developers familiar with LibreMesh and embedded systems
- 1 QA/test engineer for test design and validation
- Optional: 1 DevOps engineer for CI/CD integration

### Infrastructure

- Development workstation with virtualization capabilities
- Sufficient RAM (16GB+ recommended for multiple concurrent VMs)
- Storage space for VM images and test artifacts
- Network isolation capabilities for testing

### Dependencies

- LibreMesh source code and build dependencies
- QEMU and related virtualization tools
- Linux kernel with mac80211_hwsim support
- Network management tools (dnsmasq, iptables)
- Test frameworks and reporting tools

## Implementation Roadmap

### Month 1: Foundation

- Week 1: Environment setup and tool installation
- Week 2: Base image validation and basic networking

### Month 2: Wireless Enable

- Week 3: Wi-Fi capability integration
- Week 4: Inter-VM Wi-Fi communication

### Month 3: Network Formation

- Week 5: Multi-node infrastructure
- Week 6: Mesh network testing

### Month 4: Automation

- Week 7: Lifecycle management scripts
- Week 8: Test orchestration framework
- Week 9: Diagnostic and measurement tools

### Month 5: CI Integration

- Week 10: CI pipeline creation
- Week 11: Resource management and optimization
- Week 12: Reporting, metrics, and documentation

## Conclusion

The research indicates that automating LibreMesh testing with virtual QEMU nodes is not only feasible but has already seen significant progress through initiatives like the GSoC 2025 Wi-Fi support project. By building upon this foundation and implementing a structured, phased approach, it is possible to create a robust automated testing framework that significantly enhances the LibreMesh development process.

The proposed strategy leverages existing work while addressing identified gaps, resulting in a comprehensive solution that supports continuous integration, improves test coverage, and reduces the barrier to entry for new contributors. Success will depend on careful attention to the limitations of virtualization, thoughtful design of the automation framework, and ongoing validation against real hardware behavior.

## References

1. LibreMesh Virtualization Documentation: <https://github.com/libremesh/lime-packages/blob/master/VIRTUALIZING.md>
2. GSoC 2025 Wi-Fi Support Project: <https://blog.freifunk.net/2025/09/01/gsoc-2025-bringing-wi-fi-support-to-qemu-simulations-for-libremesh/>
3. GitHub Issue #1178 - Adding Wi-Fi Support to QEMU Simulations: <https://github.com/libremesh/lime-packages/issues/1178>
4. Alternative Virtualization Guide: <https://hackmd.io/@fd-FiKStTBGvsTvI8OKjhA/BJJuUmHMs>
5. LibreMesh SDK Information: <https://libremesh.org/build/lime-sdk.html>
6. GSoC Project Details: <https://summerofcode.withgoogle.com/programs/2025/projects/yBmMMWDN>
7. QEMU Continuous Integration Practices: <https://www.qemu.org/docs/master/devel/testing/ci.html>
