# Changelog

All notable changes to SPVS Cost & Profit for WooCommerce will be documented in this file.

## [1.4.3] - 2024-11-30

### Added
- **Built-in Data Recovery Page** - New admin page at WooCommerce > SPVS Data Recovery
  - Visual diagnostic tool for checking cost data status
  - One-click recovery from WordPress revisions
  - Shows current data count and revision backup count
  - Export current data as CSV backup
  - Automatic backup creation after recovery
  - Alternative recovery options and prevention tips
- Recovery now accessible directly from WordPress admin (no file upload needed)

### Improved
- Easier access to recovery tools (integrated into plugin menu)
- Clear visual indicators for data status (green = ok, red = missing)
- Step-by-step recovery guidance

## [1.4.2] - 2024-11-30

### Fixed
- Currency symbol display in monthly profit reports chart (was showing `&#036;` instead of `$`)
- Chart Y-axis now properly displays currency symbol without HTML entities

## [1.4.1] - 2024-11-30

### 🔒 Data Protection (Critical Update)

**IMPORTANT**: This release adds comprehensive data backup and protection to prevent cost data loss.

### Added
- **Automatic Daily Backups** - Cost data is automatically backed up every day at 3:00 AM
- **Manual Backup Creation** - Create on-demand backups with one click
- **Backup Management** - View, download, and restore from up to 7 days of backups
- **One-Click Restore** - Restore cost data from any backup (creates safety backup first)
- **Backup Export** - Download backups as CSV for external storage
- **Activation Backup** - Automatic backup created when plugin is activated/upgraded
- **Backup Rotation** - Automatically maintains 7 most recent backups
- **Recovery Tool** - Standalone diagnostic and recovery script (spvs-recovery.php)

### Improved
- Enhanced data safety during imports and updates
- Better error handling and user feedback
- Backup UI integrated into inventory admin page
- Protection against accidental data loss

### Technical
- New backup constants and methods
- Backup data stored in wp_options table
- Scheduled daily cron: `spvs_daily_cost_backup`
- New admin actions: backup, restore, export_backup
- Recovery diagnostic tool for emergency situations

## [1.4.0] - 2024-11-30

### Added
- **Monthly Profit Reports** - New dedicated admin page for viewing profit trends
  - Interactive charts powered by Chart.js
  - Customizable date range selection (defaults to last 12 months)
  - Monthly breakdown with order count, revenue, profit, and margins
  - Average profit per order calculations
  - CSV export for monthly profit data
- Revenue vs Profit comparison charts
- Profit margin percentage calculations
- Summary cards showing total profit, revenue, and average margin

### Improved
- Admin menu structure with separate "SPVS Profit Reports" page
- Better compatibility with WooCommerce HPOS for profit calculations
- Enhanced database queries for monthly report generation
- Performance optimizations for large order datasets

### Technical
- Added Chart.js CDN integration for visualizations
- New method: `get_monthly_profit_data()` for report generation
- New action: `admin_post_spvs_export_monthly_profit` for CSV exports
- New filter: `spvs_profit_report_order_statuses` to customize included order statuses
- Proper uninstall.php for complete data cleanup
- WordPress plugin repository ready documentation

## [1.3.0] - Previous Release

### Added
- CSV export for items with missing costs
- Download unmatched rows from imports
- Cost template CSV download

### Improved
- Import matching by SKU, Product ID, and Slug
- Better error handling in imports
- Enhanced product matching in CSV imports

## [1.2.0] - Previous Release

### Added
- Inventory value calculations (TCOP/Retail)
- TCOP summary bar on orders screen
- Daily automatic recalculation via cron
- CSV export/import for costs
- Customizable column selection for exports

### Improved
- Batch processing for large inventories
- Cached inventory totals for performance

## [1.1.0] - Previous Release

### Added
- Profit column to orders list
- Sortable profit column
- HPOS compatibility declaration

### Improved
- Order profit recalculation on refunds
- Better handling of order updates

## [1.0.0] - Initial Release

### Added
- Product cost field for simple and variable products
- Automatic profit calculation on checkout
- Profit display on order details
- Variation cost support with parent inheritance
- Order line item profit tracking

---

## Upgrade Notes

### Upgrading from 1.3.0 to 1.4.0
- No database changes required
- All existing data is preserved
- Monthly reports work with existing order data
- New admin page automatically appears under WooCommerce menu

### Upgrading from 1.x to 1.4.0
- Safe to upgrade - backward compatible
- No data loss
- Recommended: Back up database before any major upgrade
- After upgrade, visit WooCommerce > SPVS Profit Reports to see new features

## Breaking Changes
None in this release. All upgrades are backward compatible.

## Deprecations
None in this release.
