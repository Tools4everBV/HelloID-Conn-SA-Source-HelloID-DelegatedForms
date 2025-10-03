# Change Log
All notable changes to this project will be documented in this file. The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [1.1.0] - 06-03-2025

### Added
- **Tenant-specific export folder support:**  
  Introduced logic to dynamically calculate export folder names based on the portal URL, using the new `Get-HelloIDPortalName` function. This improves organization by grouping exports under tenant folders derived from the portal domain.
- **File/Folder naming sanitization:**  
  All export file and folder names now automatically replace problematic characters (`|` is replaced by `-`, and `&` is replaced by `AND`) to prevent issues with invalid filesystem names.
- **Changelog introduced:**  
  Added a changelog file to document all notable changes, following Keep a Changelog format and Semantic Versioning.

### Changed
- **Export structure:**  
  The root export folder now includes a subfolder named after the portal/tenant, ensuring clearer separation and easier management of exports for multiple tenants.

### Fixed
- **Folder name compatibility:**  
  Resolved potential errors and issues with folder names containing invalid characters (`|`, `&`) by sanitizing these in generated paths.

## [1.0.1] - 04-06-2025

### Fixed
- **Fixed run in cloud toggle for datasources:**  
  Resolved issue where run in cloud toggle was lost for datasources.


## [1.0.0] - 16-12-2024

This is the first official release of HelloID-Conn-SA-Source-HelloID-DelegatedForms. 
