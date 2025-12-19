# AD FS and Hybrid Azure AD Join: What You Need to Know

## Overview

This guide explains the role of Active Directory Federation Services (AD FS) in Hybrid Azure AD Join scenarios, particularly in the context of Windows Autopilot deployments with VPN connectivity.

**TL;DR**: If you're NOT using AD FS, you must disable User ESP to avoid timeouts. AD FS eliminates the 30-minute sync delay, but adds significant infrastructure complexity that most organizations don't need.

### Key Challenges with AD FS

Before considering AD FS deployment, understand these critical requirements:

1. **Certificate Challenge**: Requires publicly trusted SSL certificate with specific SANs including `enterpriseregistration.<upn-suffix>` for each UPN suffix
2. **Domain Mismatch Problem**: If your AD is `company.local` but users have `@company.com` UPNs, you'll need alternative UPN suffix configuration
3. **Infrastructure Cost**: Minimum 4 servers (2 AD FS + 2 WAP), load balancer, public IPs, and ongoing maintenance
4. **Certificate Cost**: Multi-SAN public certificates can be expensive, especially with multiple UPN suffixes

**Bottom Line**: The CSP workaround (disabling User ESP) is far simpler and achieves the same result for Hybrid Join scenarios.

## What is AD FS?

Active Directory Federation Services (AD FS) is a federation service that provides:
- Single sign-on (SSO) across organizational boundaries
- Token-based authentication using Active Directory credentials
- Claims-based authentication for federated identities

AD FS was once the go-to solution for authenticating domain users accessing Office 365. With modern Azure authentication technologies, AD FS is less commonly deployed for new implementations.

## The Hybrid Join Registration Process

### Without AD FS (Standard Azure AD Connect Sync)

When you perform a Hybrid Azure AD Join **without** AD FS, the process follows these steps:

1. **Device joins on-premises AD** (via Offline Domain Join blob from Intune Connector)
2. **Device reads SCP** (Service Connection Point) to discover Azure AD tenant information
3. **Device generates self-signed certificate** and writes it to the `userCertificate` attribute on its computer object in Active Directory
4. **Azure AD Connect syncs** the computer object (with certificate) from AD to Azure AD
   - **This sync runs every 30 minutes by default**
   - Average delay: 15 minutes
   - Worst case: 30 minutes
5. **Device polls Azure AD** repeatedly to register itself
6. **Registration succeeds** once Azure AD finds the matching device object (synced from AD)
7. **Azure AD issues device certificate** back to the device
8. **User can now get Azure AD user token** and access Intune/cloud services

### With AD FS (Federated Environment)

When you use AD FS, the process is different:

1. **Device joins on-premises AD** (via ODJ blob)
2. **Device reads SCP** to discover tenant information
3. **Device talks directly to AD FS**
4. **AD FS directly creates** the device object in Azure AD - **NO WAITING**
5. **Device registration completes immediately**
6. **User gets Azure AD token immediately** after signing in

**Key Difference**: AD FS does not require the `userCertificate` attribute synchronization, and does not need to wait for Azure AD Connect's sync cycle.

## The User ESP Problem (Without AD FS)

### Why User ESP Fails Without AD FS

The User phase of the Enrollment Status Page (ESP) tracks user-targeted apps and policies. These can only be delivered if:
- The device has completed Hybrid Azure AD Join registration
- The user has an Azure AD user token

**Without AD FS**, the hybrid join registration depends on Azure AD Connect's 30-minute sync cycle. This creates a race condition:

1. User signs in after Device ESP completes
2. User ESP starts tracking user policies/apps
3. **But the device isn't registered in Azure AD yet** (still waiting for sync)
4. User can't authenticate to Azure AD
5. Intune can't deliver user policies/apps
6. **User ESP times out** (default: 60 minutes, but nothing will happen)

### Why User ESP Works With AD FS

With AD FS:
- Device registration completes almost immediately (no sync delay)
- User signs in and gets Azure AD token right away
- User ESP can track and apply user policies/apps successfully

## Microsoft's Official Guidance

<cite index="32-1,32-2,32-3,32-4,32-5">Microsoft recommends: "Stick with Active Directory Federation Services (AD FS) if you have it deployed already. Without AD FS in the picture, the hybrid Azure AD join process requires Azure AD Connect to synchronize an endpoint-generated certificate to your Azure AD tenant. This synchronization process occurs (by default) every 30 minutes. Thus, for an individual endpoint, hybrid Azure AD join completion may take up to 30 minutes (or more depending on additional factors). AD FS does not require this certificate synchronization, and there is no delay in completing the hybrid Azure AD join process."</cite>

<cite index="32-9,32-10,32-11,32-12,32-13">Microsoft further states: "Disable the user Enrollment Status Page if you are not using AD FS. The user phase of the Enrollment Status Page (ESP) and the items it tracks only work if the endpoint has completed the hybrid Azure AD join process. Without a successful hybrid Azure AD join of the endpoint, the user cannot authenticate to Azure AD, and therefore, Intune cannot deliver policy for that user. This leads to errors and the ESP eventually times out."</cite>

## AD FS Infrastructure Requirements

If you were considering AD FS, here's what you'd need to deploy:

### Certificate Requirements

AD FS requires a **publicly trusted SSL/TLS certificate** with specific requirements:

**Certificate Must Include**:
1. **Federation Service Name** in Subject or Subject Alternative Name (SAN)
   - Example: `fs.acme.com` or `sts.acme.com`

2. **EnterpriseRegistration entries** for each UPN suffix used in your organization
   - Format: `enterpriseregistration.<upn-suffix>`
   - Example: If users have `@acme.com` UPNs, you need: `enterpriseregistration.acme.com`
   - <cite index="52-16,52-18">Microsoft requires: "For device registration or for modern authentication to on-premises resources using pre-Windows 10 clients, the SAN must contain enterpriseregistration.<upn suffix> for each User Principal Name (UPN) suffix in use in your organization."</cite>

3. **Certificate Authentication endpoint** (optional, for advanced scenarios)
   - Format: `certauth.<federation-service-name>`
   - Example: `certauth.fs.acme.com`

**Certificate Technical Requirements**:
- Must be from a **public Certificate Authority** (not self-signed for production)
- Must contain **Server Authentication** Enhanced Key Usage (EKU)
- Private key must be **exportable** (for deploying to multiple AD FS servers)
- Supports RSA 2048-bit or higher
- Does NOT support CNG keys

**Certificate Cost Consideration**: Public SSL certificates with multiple SANs can be expensive, especially if you have multiple UPN suffixes.

### Domain and UPN Suffix Challenge

**Common Scenario**: Many organizations have:
- **Internal AD Domain**: `acmecorp.local` (non-routable)
- **Email/UPN Suffix**: `@acme.com` (routable, registered domain)
- **Microsoft 365 Tenant**: `acme.onmicrosoft.com`

This creates certificate challenges:

#### The Problem

1. You **cannot** get a public SSL certificate for `.local` domains
2. Your AD domain is `acmecorp.local`, but users need UPNs like `user@acme.com`
3. AD FS certificate needs `enterpriseregistration.acme.com` in the SAN
4. You must also have a publicly accessible DNS name for the federation service (e.g., `fs.acme.com`)

#### The Solution: Alternative UPN Suffix

You need to configure an **alternative UPN suffix** in Active Directory:

**Steps**:
1. Open **Active Directory Domains and Trusts**
2. Right-click the root node → **Properties**
3. Add your routable domain as an alternative UPN suffix: `acme.com`
4. Update user accounts to use the new UPN suffix:
   ```powershell
   # Update users to use @acme.com instead of @acmecorp.local
   Get-ADUser -Filter * | Set-ADUser -UserPrincipalName "$($_.SamAccountName)@acme.com"
   ```

5. Verify the domain `acme.com` is added and verified in Microsoft 365
6. Configure Azure AD Connect to sync using the `acme.com` UPN suffix

**Certificate Example for This Scenario**:
```
Subject: CN=fs.acme.com
Subject Alternative Names:
  - fs.acme.com (federation service)
  - enterpriseregistration.acme.com (device registration)
  - certauth.fs.acme.com (optional - cert auth)
```

### Server Requirements

**Minimum for Production AD FS**:
- **AD FS Servers**: 2+ Windows Server instances (2016/2019/2022)
  - Joined to your Active Directory domain
  - Running the AD FS role
  - Behind a load balancer
  - Configured as a farm

- **Web Application Proxy (WAP) Servers**: 2+ Windows Server instances
  - In perimeter network (DMZ)
  - NOT domain-joined
  - Reverse proxy for external access
  - Same SSL certificate as AD FS servers

- **Load Balancer**:
  - Must support SNI (Server Name Indication)
  - Must NOT terminate SSL/TLS (pass-through only)
  - Health probes on HTTP (not HTTPS)

- **Database** (choose one):
  - Windows Internal Database (WID) - for small deployments (<30 servers)
  - SQL Server - for larger deployments or geographic distribution

### Network Requirements

- **Firewall Rules**:
  - TCP 443 (HTTPS) - inbound to WAP from Internet
  - TCP 443 - between WAP and AD FS servers
  - TCP 49443 - for certificate authentication (optional)

- **DNS Requirements**:
  - Public DNS A record: `fs.acme.com` → Load balancer public IP
  - Public DNS A record: `enterpriseregistration.acme.com` → Load balancer public IP
  - Internal DNS resolution for AD FS farm name

### Ongoing Maintenance

- **Certificate renewals** (annually, typically)
- **Certificate deployment** to all AD FS and WAP servers
- **Windows Updates** for all AD FS infrastructure servers
- **Monitoring** for AD FS health and availability
- **Backup** of AD FS configuration and certificates

## Do You Need AD FS?

### When AD FS Makes Sense

AD FS is beneficial if:
- **You already have AD FS deployed** - Keep using it for Hybrid Join scenarios
- **You need User ESP** to work reliably during Autopilot
- You have complex federated identity requirements across multiple organizations
- You require advanced claims-based authentication

### When AD FS Doesn't Make Sense

**Don't deploy AD FS solely for Hybrid Azure AD Join.** Here's why:

1. **Significant infrastructure overhead**:
   - Requires dedicated AD FS servers (Windows Server with AD FS role)
   - Requires Web Application Proxy (WAP) servers for external access
   - Requires load balancing for high availability
   - Requires SSL certificates for AD FS farm
   - Requires ongoing maintenance and certificate renewals

2. **Modern alternatives exist**:
   - Azure AD Password Hash Sync (PHS)
   - Azure AD Pass-Through Authentication (PTA)
   - Azure AD Seamless SSO

3. **Microsoft is moving away from AD FS**:
   - Azure AD authentication is the preferred path
   - AD FS feature development is minimal
   - Cloud-native solutions are prioritized

4. **Simple workaround exists**: Disable User ESP with a CSP policy

## Recommended Approach for Your Environment

Since you're deploying NetBird VPN for Hybrid Join scenarios **without AD FS**:

### Configuration

1. **Enable Device ESP** - Block until NetBird installs
2. **Disable User ESP** - Use CSP policy to skip it
3. **Skip Domain Connectivity Check** - Required for VPN scenarios

### Disable User ESP with CSP Policy

Create an Intune Custom Configuration Profile:

**OMA-URI Settings**:
```
Name: Skip User Status Page
OMA-URI: ./Vendor/MSFT/DMClient/Provider/MS DM Server/FirstSyncStatus/SkipUserStatusPage
Data type: String
Value: True
```

**What This Does**:
- User ESP is skipped entirely
- User reaches desktop after Device ESP completes
- Hybrid join registration completes in background (up to 30 minutes)
- User policies/apps deploy after registration completes (transparent to user)
- No timeout errors

### Trade-offs

**Without User ESP (Recommended)**:
- ✓ No timeouts during provisioning
- ✓ User reaches desktop faster
- ✓ No AD FS infrastructure needed
- ✗ User may briefly see "Account problem" messages if they open Teams/OneDrive immediately
- ✗ No visibility into user app installation progress

**With AD FS (Not Recommended for New Deployments)**:
- ✓ User ESP works reliably
- ✓ No sync delay
- ✓ Full visibility into provisioning progress
- ✗ Significant infrastructure complexity
- ✗ Ongoing maintenance burden
- ✗ Not aligned with Microsoft's cloud-first direction

## Conclusion

**For your NetBird-based Hybrid Join deployments**:
- Do NOT deploy AD FS just to avoid the User ESP issue
- Use the CSP policy to disable User ESP (as shown above)
- Accept the 30-minute background sync delay
- Focus on making Device ESP robust (which you're already doing with NetBird)

**If you already have AD FS**:
- Continue using it for Hybrid Join scenarios
- User ESP will work without modification
- Plan your eventual migration to cloud-native authentication

## Related Guides

- [GUIDE_INTUNE_OOBE.md](GUIDE_INTUNE_OOBE.md) - Main Autopilot/OOBE deployment guide
- [GUIDE_INTUNE_STANDARD.md](GUIDE_INTUNE_STANDARD.md) - Standard Intune deployment

## References

- Microsoft: "Success with remote Windows Autopilot and hybrid Azure Active Directory join"
- Michael Niehaus: "Digging into Hybrid Azure AD Join" (oofhours.com)
- <cite index="31-1">Microsoft: "Although not required, configuring Microsoft Entra hybrid join for Active Directory Federated Services (ADFS) enables a faster Windows Autopilot Microsoft Entra registration process during deployments."</cite>

<citations>
<document>
<document_type>WEB_SEARCH</document_type>
<document_id>techcommunity.microsoft.com/intune-customer-success</document_id>
</document>
<document>
<document_type>WEB_SEARCH</document_type>
<document_id>learn.microsoft.com/autopilot/windows-autopilot-hybrid</document_id>
</document>
<document>
<document_type>WEB_SEARCH</document_type>
<document_id>oofhours.com/hybrid-azure-ad-join</document_id>
</document>
</citations>
