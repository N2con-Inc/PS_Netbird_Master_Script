# Authentication Guides

This folder contains comprehensive guides related to Microsoft Entra ID (Azure AD) authentication, device join methods, and hybrid identity scenarios. While not directly related to NetBird VPN installation, these guides provide essential context for understanding how NetBird deployments integrate with enterprise authentication and device management strategies.

## Guides in This Folder

### [GUIDE_ENTRA_JOIN_TYPES.md](GUIDE_ENTRA_JOIN_TYPES.md)
**Complete guide to Microsoft Entra ID device join methods**

Explains the three device join types:
- **Microsoft Entra Registered** - BYOD/personal devices
- **Microsoft Entra Joined** - Cloud-native corporate devices
- **Microsoft Entra Hybrid Joined** - Domain-joined devices with cloud access

Includes decision trees, use cases, pros/cons, and recommendations for each join type.

**When to read**: Before deploying devices with NetBird, especially Hybrid Join scenarios

### [GUIDE_HYBRID_AUTH_METHODS.md](GUIDE_HYBRID_AUTH_METHODS.md)
**Comprehensive comparison of hybrid authentication methods**

Covers three authentication approaches:
- **AD FS** (Active Directory Federation Services) - Federated authentication
- **PHS** (Password Hash Synchronization) - Cloud authentication with synced hashes
- **PTA** (Pass-Through Authentication) - Cloud authentication validating on-premises

Includes:
- Infrastructure requirements and complexity comparison
- MFA (Multi-Factor Authentication) behavior with each method
- Conditional Access policy support and limitations
- Migration considerations and best practices

**When to read**: When planning authentication strategy for hybrid environments or evaluating AD FS alternatives

### [GUIDE_ADFS_HYBRID_JOIN.md](GUIDE_ADFS_HYBRID_JOIN.md)
**Deep dive into AD FS infrastructure for Hybrid Join scenarios**

Explains:
- Why AD FS eliminates the 30-minute Azure AD Connect sync delay
- Certificate requirements (public CA, SANs for each UPN suffix)
- Domain mismatch scenarios (company.local AD with @company.com UPNs)
- Enrollment Status Page (ESP) behavior with and without AD FS
- CSP workaround for disabling User ESP in non-AD FS environments

**When to read**: When deploying Hybrid Azure AD Joined devices via Intune/Autopilot, especially if experiencing ESP timeouts

## Relationship to NetBird Deployments

NetBird VPN deployments often intersect with these authentication concepts:

1. **Hybrid Join with NetBird** ([GUIDE_INTUNE_OOBE.md](../GUIDE_INTUNE_OOBE.md))
   - NetBird provides VPN connectivity during OOBE
   - Enables Offline Domain Join (ODJ) for Hybrid Azure AD Join
   - Allows devices to join on-premises AD without physical presence in office

2. **Authentication Method Impact**
   - Choice of AD FS, PHS, or PTA affects Hybrid Join registration timing
   - Impacts ESP behavior and deployment success rates
   - NetBird works with all three methods

3. **Join Type Selection**
   - Determines whether NetBird is needed for on-prem resource access
   - Entra Registered: NetBird provides cloud-to-on-prem connectivity
   - Entra Joined: NetBird enables SSO to on-prem file shares via Azure AD Kerberos
   - Hybrid Joined: NetBird used during provisioning and ongoing access

## Recommended Reading Order

**For new deployments**:
1. [GUIDE_ENTRA_JOIN_TYPES.md](GUIDE_ENTRA_JOIN_TYPES.md) - Understand join options
2. [GUIDE_HYBRID_AUTH_METHODS.md](GUIDE_HYBRID_AUTH_METHODS.md) - Choose authentication method
3. [GUIDE_INTUNE_OOBE.md](../GUIDE_INTUNE_OOBE.md) - Deploy NetBird with chosen approach

**For existing Hybrid Join environments**:
1. [GUIDE_ADFS_HYBRID_JOIN.md](GUIDE_ADFS_HYBRID_JOIN.md) - Understand ESP behavior
2. [GUIDE_HYBRID_AUTH_METHODS.md](GUIDE_HYBRID_AUTH_METHODS.md) - Evaluate if AD FS is needed
3. [GUIDE_INTUNE_OOBE.md](../GUIDE_INTUNE_OOBE.md) - Implement NetBird for OOBE

**For troubleshooting ESP issues**:
1. [GUIDE_ADFS_HYBRID_JOIN.md](GUIDE_ADFS_HYBRID_JOIN.md) - ESP timeout explanation and fix
2. [GUIDE_ENTRA_JOIN_TYPES.md](GUIDE_ENTRA_JOIN_TYPES.md) - Validate join type configuration

## Quick Reference: Key Decisions

### Which Join Type?
- **Personal device** → Entra Registered
- **Corporate device + no AD** → Entra Joined
- **Corporate device + existing AD** → Hybrid Joined (transitioning to Entra Joined)

### Which Authentication Method?
- **Simple, cloud-first** → PHS (Password Hash Sync)
- **Compliance requires passwords on-prem** → PTA (Pass-Through Auth)
- **Federation or partner scenarios** → AD FS (if truly needed)

### Do I Need AD FS for Hybrid Join?
- **No** - PHS or PTA work fine
- **Caveat** - User ESP will timeout (disable via CSP)
- **Exception** - AD FS eliminates sync delay (but adds complexity)

## Support and Updates

These guides are maintained as part of the NetBird Master Script project. For questions or updates:
- Review the main project README
- Check related NetBird deployment guides in parent folder
- Consult Microsoft Learn documentation for official guidance

---

**Note**: These guides focus on architectural concepts and design decisions. For NetBird-specific deployment steps, see the guides in the parent folder.
