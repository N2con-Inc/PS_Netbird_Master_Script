# Hybrid Authentication Methods: AD FS, PHS, and PTA Explained

## Overview

This guide provides in-depth analysis of authentication methods for hybrid environments where organizations need both on-premises Active Directory and Microsoft 365/Azure cloud services. It answers critical questions about AD FS requirements, alternatives, and modern authentication approaches.

**Key Questions Addressed**:
1. Why multiple AD FS servers are required and consequences of single-server deployments
2. Whether alternatives to Web Application Proxy (like NGINX, Caddy, HAProxy) are viable
3. Modern alternatives (PHS, PTA) and their pros/cons for hybrid environments

## Question 1: Why Multiple AD FS Servers?

### Single Point of Failure Risk

<cite index="64-38,64-39,64-40">When using AD FS: "Once you configure ADFS, high availability becomes extremely critical. If your ADFS infrastructure is unavailable, end users won't be able to log in to Office 365 services. Make sure your infrastructure is highly available to prevent any problems."</cite>

**What Happens with Only One AD FS Server**:

When you configure federated authentication, <cite index="61-13,61-14">users are redirected to your AD FS server for authentication</cite>. This means:

1. **ALL Office 365 authentication flows through AD FS**
   - Users signing into Office 365 web portal
   - Outlook desktop clients connecting to Exchange Online
   - Teams, SharePoint, OneDrive access
   - Mobile device access
   - Third-party apps using Microsoft 365 integration

2. **Single Server Failure = Complete Outage**
   - If the AD FS server is down (hardware failure, Windows updates, maintenance)
   - **Nobody can authenticate to Office 365** 
   - Users cannot access email, documents, collaboration tools
   - Even users already signed in will lose access when tokens expire (typically within hours)

3. **Maintenance Windows Become User Outages**
   - Windows updates requiring reboots = Office 365 outage
   - Certificate renewals = potential outage
   - Configuration changes = potential outage
   - You cannot perform maintenance without impacting all users

### Authentication Flow Dependency

<cite index="70-17">With Single Sign-on with Office 365, you rely on your local Active Directory for authentication</cite>. This creates a critical dependency chain:

```
User → Office 365 → AD FS Server → Active Directory → Back to Office 365
```

If AD FS is unavailable at any point in this chain, authentication fails completely.

### Recommended Production Architecture

<cite index="67-13,67-14,67-15,67-16">Microsoft recommends: "Ideally this server will be installed as virtual servers on multiple Hyper-V hosts. Think about redundancy, not only in the virtual servers, but in the Hyper-V servers as well. Install one AD FS and one AD FS Proxy on one Hyper-V host and the other AD FS and AD FS Proxy on another Hyper-V host. This prevents loss of service from a hardware failure."</cite>

**Minimum Recommended**:
- 2x AD FS servers (domain-joined, behind load balancer)
- 2x WAP servers (in DMZ, reverse proxy)
- 1x Load balancer (or NLB feature of Windows Server)

### Can You Run Single Server?

**Technically yes**, but:
- ✗ Not recommended for production
- ✗ Not supported by Microsoft for production Office 365
- ✗ Any downtime = complete authentication outage
- ✗ No maintenance window without user impact
- ✓ Acceptable for testing/lab environments only

**Microsoft's Official Stance**: <cite index="65-20,65-21,65-22">Each scenario can be varied by using a stand-alone AD FS server instead of a server farm. However, it's always a Microsoft best-practice recommendation that all critical infrastructure services be implemented by using high-availability technology to avoid loss of access. On-premises AD FS availability directly affects Microsoft cloud service availability for federated users.</cite>

## Question 2: Web Application Proxy Alternatives

### What WAP Actually Does

Web Application Proxy serves two critical functions for AD FS:

1. **Reverse Proxy** - <cite index="71-5,71-6">WAP servers act as reverse proxies which allow external users to access the web applications hosted on the corporate intranet</cite>

2. **Pre-Authentication Termination** - <cite index="71-10,71-11">When enabling external clients to access your AD FS servers, it's best practice to terminate the external traffic at the border between the DMZ and the corporate intranet and also to identify external authentication attempts by inserting the x-ms-proxy header. WAP servers perform both of these functions</cite>

### Can NGINX/Caddy/Traefik/HAProxy Work?

**Short Answer**: Yes, with significant caveats and limitations.

#### NGINX as WAP Replacement

**Confirmed Working**: <cite index="71-1,71-2">NGINX Plus has many features critical for HA in production AD FS environments. In the deployment of the standard topology, NGINX Plus replaces NLB to load balance traffic for all WAP and AD FS farms</cite>.

**Critical Requirements**:

1. **SSL Pass-Through (NOT Termination)**
   - <cite index="71-22">We do not have NGINX Plus terminate SSL connections for the AD FS servers, because correct AD FS operation requires it to see the actual SSL certificate from the WAP server</cite>
   - AD FS needs to inspect the client's SSL certificate for certain authentication scenarios
   - You must use `proxy_pass https://` without SSL termination

2. **Host Header Preservation**
   - <cite index="76-6,76-7">Nginx was not passing the host header in the reverse proxy request. When connecting to the backend server it was only using the IP of the upstream server causing ADFS to not accept connections</cite>
   - Must include: `proxy_set_header Host $host;`

3. **X-MS-Proxy Header**
   - <cite index="79-1">Must include: `proxy_set_header X-MS-Proxy the-nginx-machine;`</cite>
   - This identifies external authentication attempts

**NGINX Configuration Example**:
```nginx
upstream adfs_backend {
    server 192.168.1.10:443;
    server 192.168.1.11:443;
    keepalive 100;
}

server {
    listen 443 ssl;
    server_name fs.acme.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass https://adfs_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-MS-Proxy $host;
        proxy_http_version 1.1;
        proxy_ssl_server_name on;
        proxy_ssl_name $host;
    }
}
```

#### Other Alternatives

**HAProxy**: 
- ✓ Capable of SSL pass-through
- ✓ Can add custom headers
- ✓ Production-grade load balancing
- ✓ Similar configuration to NGINX

**Caddy**:
- ✓ Can work as reverse proxy
- ~ Less common in enterprise AD FS scenarios
- ~ Documentation sparse for AD FS specifically

**Traefik**:
- ✓ Can work as reverse proxy
- ✓ Good for containerized environments
- ~ Less common for AD FS (typically Windows-based)

### Limitations vs. WAP

**What You Lose with Third-Party Proxies**:

1. **Advanced Claims Rules** - <cite index="71-12">WAP servers perform both termination and header insertion, but NGINX Plus does also. WAP servers are not required for some use cases – for example, when you don't use advanced claim rules such as IP network and trust levels</cite>

2. **Constrained Delegation (KCD)**
   - WAP supports Kerberos Constrained Delegation
   - Third-party proxies typically do not

3. **Native Integration**
   - WAP is designed specifically for AD FS
   - Configuration via PowerShell cmdlets
   - Automatic updates with Windows

4. **Microsoft Support**
   - <cite index="65-22,65-23">On-premises AD FS availability is the responsibility of the customer. Third-party proxies must support the MS-ADFSPIP protocol to be supported as an AD FS proxy</cite>

### When to Use Alternatives

**Good Use Cases**:
- ✓ You already have NGINX/HAProxy infrastructure
- ✓ Simple AD FS deployment without advanced claims
- ✓ Cost savings (no additional Windows Server licenses for WAP)
- ✓ Team has stronger Linux/proxy expertise than Windows

**Avoid If**:
- ✗ You need advanced AD FS features (KCD, complex claims)
- ✗ You lack deep proxy configuration expertise
- ✗ You need guaranteed Microsoft support
- ✗ Environment is primarily Windows-based

## Question 3: Modern Alternatives (PHS & PTA)

For hybrid environments, Microsoft offers three authentication methods. Let's focus on the modern alternatives to AD FS.

### Password Hash Synchronization (PHS)

**How It Works**:
<cite index="90-3,90-4,90-5,90-6">Password hash synchronization synchronizes user password hashes from on-premises AD to Azure AD. This involves installing Microsoft Entra Connect, configuring directory synchronization, and enabling password hash synchronization</cite>.

**Technical Details**:
- <cite index="88-3,88-4">The password hash portion runs every two minutes. Depending on when the password change occurs, it could take up to two minutes before the new password is reflected in Entra ID</cite>
- <cite index="88-5">Remaining user attributes synchronize every 30 minutes</cite>
- Authentication happens **in Azure AD**, not on-premises
- Requires only 1-2 servers running Azure AD Connect

**Pros**:
- ✓ **Simplest to implement** - No additional infrastructure
- ✓ **No on-premises dependency** - Users can authenticate even if on-prem is down
- ✓ **Lowest cost** - Only requires Azure AD Connect server(s)
- ✓ **Leaked credential protection** - Azure detects compromised passwords
- ✓ **Best for disaster recovery** - Works even if on-premises is completely offline
- ✓ **No Azure charges** - Authentication is included in Azure AD licenses

**Cons**:
- ✗ **Password hashes in cloud** - Some organizations have policies against this
- ✗ **Sync delays** - <cite index="88-6">The 'enabled' attribute synchronization means decommissioning could take several minutes before flowing into Entra ID</cite>
- ✗ **Limited policy enforcement** - <cite index="88-7,88-8">Password expiration policy, "User must change password at next logon", account expiration date, and accounts in locked-out state are not natively supported</cite>
- ✗ **2-minute password change delay** - Not instant like on-premises

### Pass-Through Authentication (PTA)

**How It Works**:
<cite index="84-6,84-7,84-8,84-9">PTA allows users to authenticate directly against on-premises AD. When a user attempts to sign in, their password is validated by the on-premises AD domain controller. Unlike other methods, PTA does not store or sync the password hash to Azure AD. Instead, it relies on an agent installed on the on-premises server to handle authentication requests</cite>.

**Technical Details**:
- <cite index="89-1,89-2,89-3">Authentication happens in on-premises through authentication connector. This connector is by default installed in AD Connect server. For high availability, install the connector on another server</cite>
- Requires connectivity to on-premises infrastructure
- Authentication agents make outbound HTTPS connections to Azure AD
- No inbound firewall rules required

**Pros**:
- ✓ **No password hashes in cloud** - Passwords never leave on-premises
- ✓ **Real-time policy enforcement** - <cite index="85-1,85-3,85-4">PTA enforces Active Directory user account states, password policies, and sign-in hours in real time. If an account is disabled, expired or locked out on-premises, the user can't access cloud services either</cite>
- ✓ **Instant account changes** - No sync delay for disabled/locked accounts
- ✓ **Meets compliance requirements** - For orgs that cannot store passwords in cloud
- ✓ **No Azure charges** - Authentication is included

**Cons**:
- ✗ **On-premises dependency** - <cite index="86-26,86-27,86-28">During a temporary loss of connection with PTA agents, users may face challenges in signing in to cloud resources. To mitigate this risk, deploying multiple agents is advisable</cite>
- ✗ **More infrastructure** - Requires authentication agent servers with AD connectivity
- ✗ **More maintenance** - Additional agents to monitor and maintain
- ✗ **No automatic failover** - <cite index="82-4,82-5">Pass-through Authentication doesn't automatically failover to password hash synchronization. You should configure Pass-through Authentication for high availability</cite>

### Comparison Table

| Feature | AD FS | PHS | PTA |
|---------|-------|-----|-----|
| **Infrastructure** | 4+ servers (AD FS + WAP) | 1-2 servers (AAD Connect) | 2-3+ servers (AAD Connect + agents) |
| **Certificates Required** | Public SSL (multi-SAN) | None | None |
| **Password in Cloud** | No | Yes (hash of hash) | No |
| **Auth Location** | On-premises | Azure AD | On-premises |
| **Sync Delay** | None | 2 min (passwords), 30 min (attributes) | None |
| **On-prem Dependency** | 100% - outage = no auth | 0% - works offline | 100% - outage = no auth |
| **Policy Enforcement** | Real-time, all policies | Limited, with delays | Real-time, all policies |
| **Setup Complexity** | High | Low | Medium |
| **Ongoing Maintenance** | High | Low | Medium |
| **Cost** | High (servers, certs, licenses) | Low | Medium |
| **Microsoft Support** | Full | Full | Full |
| **Best For** | Complex requirements, federated partners | Simple, cloud-first orgs | Compliance requiring no cloud passwords |

### For Hybrid Client Environments

Based on your statement: *"Many of our clients have hybrid environments... Not all solutions can be 'cloud only' based, meaning we'll need to authenticate against local Windows servers"*

#### Authentication vs. Authorization

**Critical Distinction**: 
- **Authentication** = Proving who you are (username/password)
- **Authorization** = What you can access (file shares, printers, resources)

**You can authenticate in Azure AD (via PHS) and still access on-premises resources** via:
1. **Azure AD Kerberos** - For seamless SSO to on-premises resources
2. **Hybrid Azure AD Join** - Devices are both domain-joined and Azure AD joined
3. **Azure AD Application Proxy** - Publish on-premises apps without VPN
4. **VPN Solutions** (like NetBird) - Provide network connectivity

#### Recommended Approach for Client Environments

**Scenario: Clients need Office 365 + On-Premises File Servers**

1. **Use Password Hash Sync (PHS)** for authentication
   - Simple, reliable, works even if on-prem is down
   - Users can access Office 365 from anywhere

2. **Implement Hybrid Azure AD Join** for devices
   - Devices remain domain-joined (for GPOs, on-prem auth)
   - Also Azure AD joined (for Office 365, modern management)

3. **Deploy VPN (NetBird) for network access**
   - Provides connectivity to on-premises file servers
   - No need for AD FS complexity

4. **Result**:
   - ✓ Users authenticate to Azure AD (PHS)
   - ✓ Devices enforce on-premises GPOs (Hybrid Join)
   - ✓ File server access works (Kerberos + VPN)
   - ✓ Office 365 works everywhere
   - ✓ Minimal infrastructure (no AD FS, no WAP)
   - ✓ Lowest cost and maintenance

**Scenario: Client has strict compliance (no passwords in cloud)**

1. **Use Pass-Through Authentication (PTA)**
   - Passwords stay on-premises
   - Real-time policy enforcement

2. **Deploy 2-3 PTA agents** for high availability
   - On domain-joined servers with DC connectivity
   - Agents make outbound HTTPS only

3. **Same benefits as PHS** except:
   - ~ Slightly more infrastructure
   - ~ On-premises dependency for auth

**When to Actually Use AD FS**:
- Client needs federation with **external partners** (B2B scenarios)
- Client already has AD FS deployed and working
- Client needs **advanced claims transformation** or **custom auth flows**
- Client has budget and expertise for ongoing AD FS maintenance

**When NOT to Use AD FS**:
- "We need to authenticate against local servers" - This is **not** a reason for AD FS
- "We use on-premises file shares" - Use PHS/PTA + Hybrid Join instead
- "We need GPOs to work" - Use Hybrid Join, not AD FS
- Budget/staffing constraints - AD FS requires significant investment

## Recommendations by Organization Size

### Small (<100 users)
**Use**: Password Hash Sync (PHS)
- Minimal infrastructure
- Lowest maintenance
- Works offline

### Medium (100-1000 users)  
**Use**: Password Hash Sync (PHS) or Pass-Through Auth (PTA)
- PHS if simplicity is priority
- PTA if compliance requires no cloud passwords

### Large (1000+ users) with Existing AD FS
**Consider**: Migrating to PHS/PTA
- <cite index="82-37">If you're migrating from AD FS to Pass-through Authentication, Microsoft highly recommends following the quickstart guide</cite>
- Cost savings are substantial
- Reduced complexity

### Enterprise with Federation Requirements
**Use**: AD FS (but only if truly needed)
- Partner federations
- Custom claims
- Advanced scenarios

## Migration Path from AD FS

If you have clients currently on AD FS who want to simplify:

1. **Enable PHS alongside AD FS** (as backup)
2. **Test PHS with pilot users**
3. **Switch primary authentication to PHS/PTA**
4. **Decommission AD FS infrastructure**
5. **Save 4-6 servers + certificates + maintenance costs**

## Conclusion

**For most hybrid environments**:
- Use **Password Hash Sync** unless there's a specific reason not to
- Use **Pass-Through Authentication** if passwords cannot be in cloud
- **Avoid AD FS** unless you have genuine federation or advanced requirements
- "Authenticating against local servers" is solved by **Hybrid Join + VPN**, not AD FS

**Bottom Line**: The complexity and cost of AD FS is rarely justified for simple hybrid scenarios. Modern alternatives (PHS/PTA) provide better reliability, lower cost, and easier maintenance while still supporting on-premises resource access.

## Related Guides

- [GUIDE_ADFS_HYBRID_JOIN.md](GUIDE_ADFS_HYBRID_JOIN.md) - AD FS certificates and infrastructure details
- [GUIDE_INTUNE_OOBE.md](GUIDE_INTUNE_OOBE.md) - Hybrid Azure AD Join with VPN

<citations>
<document>
<document_type>WEB_SEARCH</document_type>
<document_id>techtarget.com/adfs-server-office-365</document_id>
</document>
<document>
<document_type>WEB_SEARCH</document_type>
<document_id>learn.microsoft.com/ad-fs-support-scenarios</document_id>
</document>
<document>
<document_type>WEB_SEARCH</document_type>
<document_id>f5.com/nginx-adfs-high-availability</document_id>
</document>
<document>
<document_type>WEB_SEARCH</document_type>
<document_id>k21academy.com/pta-phs-adfs-comparison</document_id>
</document>
<document>
<document_type>WEB_SEARCH</document_type>
<document_id>learn.microsoft.com/pass-through-authentication-faq</document_id>
</document>
</citations>
