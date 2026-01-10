# Microsoft Entra ID Device Join Types: Complete Guide

## Overview

Microsoft Entra ID (formerly Azure Active Directory) offers three distinct device join methods, each designed for different device ownership models, management requirements, and resource access scenarios. This guide helps IT administrators understand when to use each join type and what to expect from each approach.

**The Three Join Types**:
1. **Microsoft Entra Registered** - Personal devices with light cloud access (BYOD)
2. **Microsoft Entra Joined** - Corporate-owned cloud-managed devices
3. **Microsoft Entra Hybrid Joined** - Domain-joined devices extended to cloud

## Quick Comparison Table

| Feature | Entra Registered | Entra Joined | Hybrid Joined |
|---------|------------------|--------------|---------------|
| **Device Ownership** | Personal/BYOD | Corporate-owned | Corporate-owned |
| **Primary Use Case** | Access work apps from personal device | Cloud-first managed device | Domain-joined + cloud access |
| **Local Sign-In** | Personal account (local/MSA) | Work account (Entra ID) | Domain account (AD) |
| **OS Support** | Windows, macOS, iOS, Android, Linux | Windows 10/11, macOS (preview) | Windows only (7/8.1/10/11) |
| **On-Prem Infrastructure** | Not required | Not required | **Required** (AD + AAD Connect) |
| **Device Management** | Optional (MDM) | Required (Intune/MDM) | Optional (GPO + Intune) |
| **Cloud SSO** | Yes (limited) | Yes (full) | Yes (full) |
| **On-Prem SSO** | No | Via Kerberos | Yes (native) |
| **Conditional Access** | Yes | Yes | Yes |
| **Setup Complexity** | Low | Medium | High |
| **Best For** | BYOD scenarios | New deployments, cloud-first orgs | Existing AD environments |

## 1. Microsoft Entra Registered (BYOD)

### What It Is

Entra Registered devices are **personal devices** (BYOD) that gain a lightweight identity in Entra ID without requiring organizational sign-in at the device level. Users sign in locally with their personal credentials but can access work resources through registered apps.

### How It Works

1. User has personal device (home PC, personal phone, etc.)
2. User accesses work resource (e.g., Outlook mobile, company portal)
3. Device registers with Entra ID, creating a device object
4. User authenticates with work account for that specific app
5. Conditional Access policies can now evaluate device state
6. Device remains under user's personal control

**Registration Methods**:
- **Windows**: Settings > Accounts > Access work or school > Connect
- **iOS/Android**: Install Company Portal or Microsoft Authenticator
- **macOS**: Company Portal app
- **Linux**: Intune Agent (Ubuntu 20.04/22.04/24.04, RHEL 8/9)

### Use Cases

**Perfect For**:
- Employees accessing work email on personal phones
- Contractors using home computers to access SharePoint
- Seasonal workers with personal devices
- BYOD programs where org needs Conditional Access but not full control
- Accessing work apps without full device management

**Example Scenario**:
> Marketing contractor has personal MacBook. Company requires MFA and compliant device for accessing SharePoint. Contractor registers device via Company Portal, enrolls in basic Intune compliance policy (screen lock, encryption). Can now access SharePoint with personal device while company maintains access control.

### Requirements

**Technical**:
- Supported OS: Windows 10+, macOS 10.15+, iOS 15+, Android, Linux (Ubuntu/RHEL)
- Internet connectivity to `login.microsoftonline.com`, `device.login.microsoftonline.com`
- User account in Entra ID

**Licensing**:
- Entra ID Free (basic registration)
- Entra ID Premium P1/P2 (for Conditional Access, advanced policies)
- Intune license (if using MDM compliance policies)

### Pros

- **Minimal friction** - Easy user self-service enrollment
- **Broad OS support** - Works on virtually any platform
- **Privacy-friendly** - User retains device control
- **Cloud SSO** - Single sign-on to work apps and services
- **No infrastructure** - No on-premises requirements
- **Low admin overhead** - Lightweight management

### Cons

- **No device-level SSO** - User must sign in to each work app
- **Limited control** - Cannot enforce full OS policies without MDM
- **No on-prem SSO** - Cannot access on-premises file shares seamlessly
- **User-initiated** - Relies on users to register devices
- **Local credentials separate** - Work account doesn't control device sign-in
- **No Group Policy** - Cannot apply domain GPOs

### Limitations

- No seamless access to on-premises resources (file shares, printers)
- Cannot use Windows Hello for Business for device sign-in
- Conditional Access limited to registered apps only
- No unified write filter support on Windows
- Requires user to manually register device

### When to Use

**Use Entra Registered When**:
- Device is personally owned
- User needs access to cloud resources only (Office 365, SaaS apps)
- Organization wants Conditional Access without full device management
- BYOD policy allows personal device access
- Users are remote/distributed with no on-prem access needs

**Avoid When**:
- Device is company-owned (use Entra Joined instead)
- Need deep OS-level policy enforcement (use full join)
- Require seamless on-prem file share access (use Hybrid Join)
- Need device-level sign-in control

## 2. Microsoft Entra Joined (Cloud-Native)

### What It Is

Entra Joined devices are **corporate-owned devices** that authenticate directly against Entra ID using organizational accounts for device sign-in. This is the modern, cloud-native approach to device management without requiring on-premises Active Directory.

### How It Works

1. Device is provisioned (new or reset)
2. During OOBE (Out-of-Box Experience) or Settings, device joins Entra ID
3. User signs in to device with work account (user@company.com)
4. Device is automatically enrolled in MDM (Intune) if configured
5. Policies, apps, and certificates deploy from cloud
6. User has SSO to cloud AND on-premises resources (via Azure AD Kerberos)

**Enrollment Methods**:
- **Windows Autopilot** - Zero-touch deployment for new devices
- **OOBE** - User joins during Windows setup
- **Settings** - Existing device joins via Settings > Accounts
- **Bulk enrollment** - For kiosks and shared devices
- **Apple Automated Device Enrollment** - macOS (preview)

### Use Cases

**Perfect For**:
- Cloud-first or cloud-only organizations
- New device deployments (laptops, tablets, kiosks)
- Remote workers with no on-prem infrastructure access needs
- Branch offices with modern management requirements
- Temporary/seasonal workforce devices
- Organizations migrating away from on-premises AD

**Example Scenarios**:

> **Scenario 1**: SaaS startup with 200 employees, no on-premises servers. All devices are Entra Joined, managed via Intune. Users sign in with work accounts, get SSO to Office 365, Salesforce, Slack. Zero on-prem infrastructure.

> **Scenario 2**: Manufacturing company deploys shared kiosks on factory floor. Devices are Entra Joined in kiosk mode, locked down via Intune policies. Multiple workers sign in throughout the day with work credentials.

> **Scenario 3**: Enterprise with 50 branch offices transitions from domain-joined to Entra Joined for new laptop deployments. Uses Autopilot for white-glove provisioning. Users get SSO to on-prem file servers via Azure AD Kerberos + NetBird VPN.

### Requirements

**Technical**:
- **Windows**: 10 or 11, Pro/Enterprise/Education (NOT Home edition)
- **macOS**: Supported versions (public preview, limited availability)
- Internet connectivity during OOBE to `login.microsoftonline.com`, `enterpriseregistration.windows.net`
- MDM solution (Intune recommended)

**Licensing**:
- Entra ID Premium P1 or P2 (for Conditional Access, device-based policies)
- Microsoft Intune (for device management)
- Windows 10/11 Pro or Enterprise
- Autopilot deployment requires Intune + Autopilot licenses

**Network**:
- Internet access to Entra ID endpoints
- VPN solution (like NetBird) if accessing on-prem resources

### Pros

- **Modern management** - Cloud-based MDM, no domain controllers
- **Full device SSO** - Sign in once with work account, access everything
- **Cloud + on-prem SSO** - Via Azure AD Kerberos, seamless file share access
- **Conditional Access** - Full device-based policy enforcement
- **Windows Hello for Business** - Passwordless sign-in, biometrics
- **FIDO2 security keys** - Hardware-based authentication
- **Autopilot provisioning** - Zero-touch deployment
- **No on-prem infrastructure** - No domain controllers, no AD Connect
- **Self-service recovery** - Users can reset own devices via Intune

### Cons

- **OS limitations** - Windows 10/11 only (macOS preview limited)
- **No Windows Home** - Requires Pro/Enterprise/Education
- **Initial setup complexity** - Autopilot config, Intune policies
- **Licensing costs** - Requires Entra P1/P2 + Intune
- **Cloud dependency** - Sign-in requires internet (cached credentials available)
- **No Group Policy** - Must use Intune/MDM policies (GPO replacement)

### Limitations

- Cannot join Windows Home edition
- macOS support in public preview (limited features)
- No native support for on-prem apps requiring domain membership (workarounds exist)
- Requires internet for first sign-in (subsequent sign-ins cache credentials)
- Some legacy apps may not recognize Entra Joined devices

### When to Use

**Use Entra Joined When**:
- Starting fresh deployment with corporate-owned devices
- Organization is cloud-first or cloud-only
- Migrating away from on-premises Active Directory
- Need modern management without domain infrastructure
- Remote/distributed workforce
- Deploying new Windows devices via Autopilot
- Want to eliminate domain controllers

**Avoid When**:
- Need Windows Home edition support
- Heavily dependent on Group Policy (not yet ready to migrate to Intune)
- Legacy applications absolutely require domain membership
- Existing infrastructure heavily invested in AD with no migration plan

## 3. Microsoft Entra Hybrid Joined (Best of Both Worlds)

### What It Is

Hybrid Joined devices are **domain-joined devices** that also register with Entra ID, creating a dual identity that provides SSO to both on-premises and cloud resources. This bridges traditional AD environments with modern cloud authentication.

### How It Works

1. Device joins on-premises Active Directory (traditional domain join)
2. Azure AD Connect synchronizes device object to Entra ID
3. Device automatically registers with Entra ID via Service Connection Point (SCP)
4. Device now has both domain identity (for on-prem) and Entra ID identity (for cloud)
5. Users sign in with domain credentials, get SSO to both environments
6. Can be managed via GPO (on-prem) and Intune (cloud) simultaneously

**Registration Process**:
- Device joins on-premises AD via traditional methods (NETDOM, SCCM, GPO, etc.)
- Azure AD Connect sync pushes device object to Entra ID
- SCP configuration tells device to register with Entra ID
- Device registers automatically (managed authentication) or via AD FS (federated)
- Registration completes, device appears in Entra ID portal

### Use Cases

**Perfect For**:
- Existing domain-joined environments transitioning to cloud
- Organizations with on-prem servers and cloud services
- Enabling Conditional Access for domain-joined devices
- Gradual cloud migration without disrupting existing workflows
- Enterprises heavily invested in Active Directory
- Need SSO to both on-prem file shares AND Office 365

**Example Scenarios**:

> **Scenario 1**: Enterprise with 5,000 domain-joined Windows laptops wants to enable Conditional Access for Office 365 without re-imaging devices. Configures Hybrid Join via Azure AD Connect, all devices register automatically. Users now get SSO to SharePoint Online and on-prem file servers.

> **Scenario 2**: Healthcare org with mix of cloud apps (Office 365) and on-prem apps (EMR system on local servers). Hybrid Join enables SSO to both, Conditional Access protects cloud resources, GPO enforces on-prem policies.

> **Scenario 3**: Financial services company migrating to cloud over 3 years. Uses Hybrid Join to modernize authentication incrementally while maintaining on-prem infrastructure during transition.

### Requirements

**Technical**:
- **On-Premises**:
  - Active Directory Domain Services (AD DS) functional level Windows Server 2008 R2+
  - Azure AD Connect version 1.1.819.0 or later
  - Service Connection Point (SCP) configured in AD
  - For federated domains: AD FS with WS-Trust endpoints enabled
  
- **Network Connectivity** (from domain devices to internet):
  - `enterpriseregistration.windows.net`
  - `login.microsoftonline.com`
  - `device.login.microsoftonline.com`
  - `autologon.microsoftazuread-sso.com` (for Seamless SSO)

- **Supported OS**:
  - Windows 10 or 11 (most common)
  - Windows 8.1
  - Windows 7 (with caveats, end-of-life)
  - Windows Server 2016+ (limited scenarios)

**Licensing**:
- Entra ID Premium P1 or P2 (for Conditional Access)
- Azure AD Connect (free)
- Windows licenses (as applicable)
- Intune (if co-managing with GPO)

**Infrastructure**:
- Active Directory domain controllers
- Azure AD Connect sync server
- AD FS farm (if using federated authentication)
- Firewall rules allowing device registration traffic

### Pros

- **Dual SSO** - Seamless access to on-prem AND cloud resources
- **No device re-imaging** - Existing domain-joined devices upgrade in-place
- **Conditional Access** - Modern security for legacy devices
- **Gradual migration** - Modernize authentication without full cloud migration
- **Group Policy + Intune** - Co-management capabilities
- **User experience unchanged** - Users sign in as always (domain credentials)
- **On-prem app compatibility** - Legacy apps continue working

### Cons

- **High complexity** - Most complex join method
- **On-prem dependency** - Requires AD, AAD Connect, network connectivity
- **Dual management** - Must manage both AD and Entra ID
- **Sync delays** - Device changes take time to replicate (Azure AD Connect cycles)
- **Troubleshooting complexity** - Issues can stem from on-prem or cloud
- **Infrastructure overhead** - Domain controllers, sync servers, maintenance
- **Windows only** - No macOS, iOS, Android, Linux support

### Limitations

- Requires on-premises Active Directory (cannot use Hybrid Join without AD)
- Azure AD Connect sync required (adds infrastructure and maintenance)
- Registration can fail if network connectivity to Entra ID is blocked
- Federated domains require AD FS with specific WS-Trust configuration
- Device object sync delays can cause registration issues
- No support for non-Windows devices
- More complex troubleshooting (dual identity systems)

### When to Use

**Use Hybrid Join When**:
- Existing domain-joined Windows fleet (hundreds or thousands of devices)
- Need SSO to both on-prem file shares AND cloud apps
- Gradual cloud migration strategy (not immediate cloud-only)
- Legacy applications require domain membership
- Heavy investment in Active Directory infrastructure
- Want to enable Conditional Access without re-imaging devices
- Co-management scenarios (GPO + Intune)

**Avoid When**:
- Starting from scratch (use Entra Joined instead)
- Cloud-only or cloud-first organization
- No on-premises Active Directory
- Want to eliminate domain infrastructure
- Small deployment where complexity isn't justified
- Non-Windows devices

## Special Considerations

### Enrollment Status Page (ESP) and Hybrid Join

**Important**: When deploying Hybrid Joined devices via Intune, be aware of ESP behavior:

- **User ESP Phase Issue**: Hybrid join registration takes up to 30 minutes (Azure AD Connect sync cycle)
- **ESP Timeout**: User ESP times out before hybrid join completes (without AD FS)
- **Solution**: Disable User ESP via CSP policy for Hybrid Join scenarios
- **AD FS Exception**: With AD FS, registration is immediate (no sync delay)

See [GUIDE_ADFS_HYBRID_JOIN.md](GUIDE_ADFS_HYBRID_JOIN.md) for details.

### Authentication Methods for Hybrid Environments

Hybrid Join works with all three authentication methods:
- **AD FS** (federated) - Immediate registration, most complex
- **Password Hash Sync (PHS)** - Simple, 30-min sync delay
- **Pass-Through Auth (PTA)** - Middle ground, 30-min sync delay

See [GUIDE_HYBRID_AUTH_METHODS.md](GUIDE_HYBRID_AUTH_METHODS.md) for comprehensive comparison.

## Decision Tree: Which Join Type?

```
Is the device corporate-owned?
├─ NO → Use Entra Registered (BYOD)
└─ YES
    │
    Do you have on-premises Active Directory?
    ├─ NO → Use Entra Joined (cloud-native)
    └─ YES
        │
        Is this an existing domain-joined device?
        ├─ YES → Use Hybrid Join (extend to cloud)
        └─ NO (new device)
            │
            Do you still need domain membership?
            ├─ YES → Use Hybrid Join (domain join + cloud)
            └─ NO → Use Entra Joined (cloud-native)
```

## Recommendations by Scenario

### Small Business (<100 users, no AD)
**Use**: Entra Joined
- No on-prem infrastructure needed
- Modern management via Intune
- Cloud SSO to Office 365 and SaaS apps

### Mid-Size (100-1000 users, existing AD)
**Use**: Hybrid Join (short-term) → Entra Joined (long-term)
- Hybrid Join enables Conditional Access today
- Plan migration to cloud-native over time
- New devices go Entra Joined

### Enterprise (1000+ users, established AD)
**Use**: Hybrid Join + Entra Joined (hybrid approach)
- Hybrid Join for existing fleet
- Entra Joined for new deployments
- Gradual shift to cloud-native

### BYOD Program (any size)
**Use**: Entra Registered
- Personal devices access work resources
- Conditional Access without full management
- User privacy maintained

### Cloud-First Startup
**Use**: Entra Joined exclusively
- No on-prem infrastructure
- Modern management from day one
- Autopilot for zero-touch deployment

## Device Management Comparison

| Capability | Entra Registered | Entra Joined | Hybrid Joined |
|------------|------------------|--------------|---------------|
| **BitLocker Encryption** | Via MDM (if enrolled) | Yes (Intune) | Yes (GPO or Intune) |
| **Windows Hello for Business** | No | Yes | Yes |
| **FIDO2 Sign-In** | No | Yes | No (currently) |
| **MDM Enrollment** | Optional | Automatic | Optional (co-management) |
| **Group Policy** | No | No | Yes |
| **Intune Policies** | If MDM enrolled | Yes | Yes (co-management) |
| **Conditional Access** | Yes (limited) | Yes (full) | Yes (full) |
| **Device Compliance** | If MDM enrolled | Yes | Yes |
| **App Deployment** | Via MDM | Via Intune | Via GPO or Intune |
| **Remote Wipe** | If MDM enrolled | Yes | Via Intune (if enrolled) |

## SSO Behavior Comparison

| Resource Type | Entra Registered | Entra Joined | Hybrid Joined |
|---------------|------------------|--------------|---------------|
| **Cloud Apps (Office 365, Azure)** | Yes (per-app sign-in) | Yes (seamless) | Yes (seamless) |
| **SaaS Apps (Salesforce, etc.)** | Yes (per-app sign-in) | Yes (seamless) | Yes (seamless) |
| **On-Prem File Shares (SMB)** | No | Via Azure AD Kerberos + VPN | Yes (native) |
| **On-Prem Apps (IIS/Kerberos)** | No | Via Azure AD Kerberos + VPN | Yes (native) |
| **Legacy Apps (NTLM)** | No | Limited | Yes (native) |
| **Web Apps (WIA)** | No | Yes (if configured) | Yes (native) |

## Troubleshooting Tips

### Entra Registered Issues
- Check device registration: `dsregcmd /status` (Windows)
- Verify MDM enrollment in Intune portal
- Confirm Conditional Access policies allow registered devices
- Check user has internet connectivity to Entra endpoints

### Entra Joined Issues
- Verify device shows in Entra ID portal as "Joined" (not "Registered")
- Check Autopilot deployment status if used
- Confirm user is signing in with work account (not local)
- Run `dsregcmd /status` - look for "AzureAdJoined: YES"
- Verify Intune enrollment completed

### Hybrid Joined Issues
- Most complex troubleshooting - dual identity
- Check `dsregcmd /status` - both "DomainJoined: YES" and "AzureAdJoined: YES"
- Verify Azure AD Connect sync is healthy
- Confirm SCP configuration in AD
- Check network connectivity to registration endpoints
- Review event logs: Applications and Services Logs > Microsoft > Windows > User Device Registration
- Verify device object exists in both AD and Entra ID portal
- For federated: Confirm AD FS is healthy and WS-Trust endpoints enabled

## Conclusion

Choosing the right Entra ID join type is foundational to your device management strategy:

- **Entra Registered** for BYOD and personal devices
- **Entra Joined** for cloud-native, corporate-owned devices
- **Hybrid Joined** for existing AD environments transitioning to cloud

Modern organizations should favor **Entra Joined** for new deployments and gradually migrate Hybrid Joined devices as on-premises dependencies decrease. The long-term goal for most organizations is cloud-native management without on-premises infrastructure complexity.

## Related Guides

- [GUIDE_HYBRID_AUTH_METHODS.md](GUIDE_HYBRID_AUTH_METHODS.md) - AD FS, PHS, and PTA comparison
- [GUIDE_ADFS_HYBRID_JOIN.md](GUIDE_ADFS_HYBRID_JOIN.md) - AD FS infrastructure for Hybrid Join
- [GUIDE_INTUNE_OOBE.md](../GUIDE_INTUNE_OOBE.md) - Hybrid Join with NetBird VPN deployment
