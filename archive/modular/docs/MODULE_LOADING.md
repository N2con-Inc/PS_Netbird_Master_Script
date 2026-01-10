# Module Loading - Critical Implementation Details

## The PowerShell Scoping Problem

### Problem
When dot-sourcing (`. script.ps1`) **inside a function**, the loaded functions only become available in that **function's local scope**, NOT the script scope where other functions run.

### Example of the Problem
```powershell
# BAD - Functions won't be available outside Import-Module
function Import-Module {
    . C:\module.ps1  # Functions load into Import-Module's scope only!
}

Import-Module
Get-SomeFunction  # ERROR: Function not found!
```

### Why This Happens
PowerShell scoping rules:
- **Script scope**: Available to all functions in the script
- **Local scope**: Only available within the current function
- **Global scope**: Available everywhere

When you dot-source inside a function, PowerShell loads the content into the **local scope** of that function, not the script scope.

## The Solution

### Use Invoke-Expression to Force Script Scope
```powershell
function Import-Module {
    # CORRECT - Load into script scope
    $script:__ModuleToLoad = $modulePath
    Invoke-Expression ". `$script:__ModuleToLoad"
}

Import-Module
Get-SomeFunction  # SUCCESS: Function available!
```

### How It Works
1. Store the path in a **script-scoped variable** (`$script:__ModuleToLoad`)
2. Use `Invoke-Expression` to execute the dot-source command
3. Because the variable is script-scoped, the dot-source happens at script level
4. Functions become available to all functions in the script

## Implementation in This Project

### All Module Loading Uses This Pattern

The `Import-NetBirdModule` function has **three loading paths**, and ALL use the same pattern:

#### 1. Cached Module (Line 356)
```powershell
$script:__ModuleToLoad = $cachedModulePath
Invoke-Expression ". `$script:__ModuleToLoad"
```

#### 2. Local Module (Line 379)
```powershell
$script:__ModuleToLoad = $localModulePath
Invoke-Expression ". `$script:__ModuleToLoad"
```

#### 3. Downloaded Module (Line 401)
```powershell
$script:__ModuleToLoad = $cachedModulePath
Invoke-Expression ". `$script:__ModuleToLoad"
```

## Adding New Module Loading Code

### ⚠️ CRITICAL RULE ⚠️

**NEVER** dot-source directly inside a function:
```powershell
# ❌ WRONG - Functions won't be available
. $modulePath
```

**ALWAYS** use the Invoke-Expression pattern:
```powershell
# ✅ CORRECT - Functions available everywhere
$script:__ModuleToLoad = $modulePath
Invoke-Expression ". `$script:__ModuleToLoad"
```

### Template for New Loading Code
```powershell
function Import-CustomModule {
    param([string]$Path)
    
    # Validate path
    if (-not (Test-Path $Path)) {
        throw "Module not found: $Path"
    }
    
    # CRITICAL: Use script scope loading pattern
    $script:__ModuleToLoad = $Path
    Invoke-Expression ". `$script:__ModuleToLoad"
    
    # Verify loading (optional but recommended)
    if (Get-Command SomeExpectedFunction -ErrorAction SilentlyContinue) {
        Write-Host "Module loaded successfully"
    } else {
        throw "Module loaded but expected functions not available"
    }
}
```

## Why Not Use Import-Module?

PowerShell's `Import-Module` cmdlet would solve this, but:
1. Requires creating proper `.psm1` module files with manifests
2. More complex to manage for simple script modularization
3. Our current architecture uses simple `.ps1` files for simplicity
4. The Invoke-Expression pattern works perfectly for our use case

If this project grows significantly, consider converting to proper PowerShell modules.

## Testing Module Loading

### Verify Functions Are Available
After loading a module, test that functions are accessible:

```powershell
# Load module
Import-NetBirdModule -ModuleName "version" -Manifest $manifest

# Verify function availability
if (Get-Command Get-LatestVersionAndDownloadUrl -ErrorAction SilentlyContinue) {
    Write-Host "✓ Function available"
} else {
    Write-Error "✗ Function NOT available - scoping issue!"
}
```

### Debug Scoping Issues
If functions aren't available after loading:

1. **Check where dot-sourcing happens**
   - Inside a function? ❌ Won't work
   - Using Invoke-Expression with script variable? ✅ Will work

2. **Verify the pattern**
   ```powershell
   # Must have BOTH lines
   $script:__ModuleToLoad = $path  # Script-scoped variable
   Invoke-Expression ". `$script:__ModuleToLoad"  # Invoke-Expression
   ```

3. **Check for errors during loading**
   - If the module has syntax errors, it may load without throwing but functions won't be defined
   - Wrap in try/catch and log exceptions

## References

- [PowerShell about_Scopes](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scopes)
- [PowerShell Dot Sourcing](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scripts#script-scope-and-dot-sourcing)
- [Invoke-Expression Cmdlet](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-expression)

## Version History

- **v1.3.0** (2025-12-18): Fixed critical scoping issue by implementing Invoke-Expression pattern for all module loading
- All three loading paths (cached, local, downloaded) now use the script scope pattern
- Added comprehensive documentation to prevent regression
