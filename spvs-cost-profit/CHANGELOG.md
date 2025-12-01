# Changelog

All notable changes to SPVS Cost & Profit for WooCommerce will be documented in this file.

## [1.5.4] - 2024-12-01

### Fixed
- **TCOP Calculation** - Reverted to only count products with stock management enabled AND quantity > 0
  - TCOP = Total cost of products in stock (managed stock with qty > 0)
  - Retail = Total retail value of products in stock (managed stock with qty > 0)
  - Spread = Retail - TCOP
  - Products without stock management or with zero quantity are NOT counted
- **Order Recalculation Network Error** - Fixed `wc_orders_count()` undefined function error
  - Now uses `wc_get_orders()` with `return => 'ids'` to count orders
  - Properly caches total count in transient for batch processing

### Technical
- Removed `with_cost` counter from inventory totals option
- Updated order recalculation to use standard WooCommerce functions
- Simplified TCOP calculation logic back to original stock-based approach

## [1.5.3] - 2024-12-01

### Added
- **Historical Order Profit Recalculation** - Recalculate profit for all past orders using current cost data
  - New "Recalculate All Orders" button on profit reports page
  - Real-time progress modal with batch processing (20 orders per batch)
  - Forces recalculation even if profit was previously calculated
  - Perfect for after importing costs from Cost of Goods or other sources
  - Batch processing with 500ms delays to prevent server overload

### Changed
- **TCOP Calculation Logic** - Now includes ALL products with costs set
  - Previous: Only counted products with stock management enabled and quantity > 0
  - Now: Counts all products with costs, uses quantity of 1 for non-stock-managed products
  - Stock-managed products with zero quantity are still excluded from totals
  - More accurate inventory valuation for catalogs without stock management

### Fixed
- TCOP showing $0 after Cost of Goods import due to products not having stock management enabled
- Historical orders showing $0 profit/margin when costs were imported after orders were placed

### Technical
- New AJAX endpoint: `wp_ajax_spvs_recalc_orders_batch`
- New JavaScript file: `js/order-recalc.js` for recalculation progress tracking
- Order profit recalculation: `ajax_recalc_orders_batch()` method
- Forces recalculation by deleting stored profit meta before recalculating
- Updated inventory totals option to include `with_cost` counter
- Modal CSS updated to support both import and recalculation modals

## [1.5.2] - 2024-12-01

### Added
- **Import Options UI** - User-selectable import behavior
  - Checkbox: "Overwrite existing costs" (checked by default)
  - Checkbox: "Delete Cost of Goods data after import" (optional cleanup)
  - Confirmation dialog shows selected options before import
  - Options stored and respected across all batch operations

### Changed
- Import behavior now respects user selection:
  - **Overwrite ON:** Replaces all existing costs with COG data
  - **Overwrite OFF:** Only imports products without existing costs
- Import confirmation dialog now shows warnings based on selected options

### Improved
- Added COG data cleanup option to avoid data duplication
- Deletes `_wc_cog_cost` meta after import if "Delete after import" is checked
- More flexible import workflow - users control overwrite behavior
- Better user experience with clear option explanations

### Technical
- New checkboxes: `#spvs-cog-overwrite` and `#spvs-cog-delete-after`
- JavaScript passes options via AJAX: `overwrite` and `delete_after` parameters
- Options stored in transient for consistency across batches
- Per-product `delete_post_meta()` for `_wc_cog_cost` when delete_after enabled
- Transients cleaned up on import completion

## [1.5.1] - 2024-12-01

### Changed
- **Import Behavior - Full Overwrite** - Cost of Goods import now overwrites ALL existing costs
  - Previous: Only updated if values were different (causing skips)
  - Now: Always overwrites with COG data, regardless of existing value
  - Still skips products with zero or empty COG values
  - Updated UI to clarify that this is a full overwrite operation

### Technical
- Simplified import logic to always call `update_post_meta()` for non-zero COG values
- Removed conditional checks that compared existing vs new values
- "Updated" counter now tracks any product that had an existing cost (even if same value)
- "Imported" counter tracks products that had no existing cost

## [1.5.0] - 2024-12-01

### Added
- **Real-Time Progress Modal** - Visual progress tracking for Cost of Goods import
  - Live progress bar showing percentage complete
  - Real-time counters: Imported, Updated, Skipped, Processed
  - AJAX-based batch processing with visual feedback
  - Modal overlay prevents page navigation during import
  - "Close & Reload Page" button when complete
  - Success message shown after modal closes

### Improved
- Import now uses AJAX instead of page reload
- Better user experience with visual progress feedback
- Import completion summary shown only after all products processed
- No more guessing if import is still running or stuck

### Technical
- New AJAX action: `wp_ajax_spvs_cog_import_batch`
- JavaScript file: `js/cog-import.js` with jQuery-based progress handling
- Inline CSS for modal styling (no external CSS file needed)
- Progress data stored in transients during multi-batch processing
- 1 second delay between batches maintained for server health

## [1.4.9] - 2024-12-01

### Improved
- **Import Throttling** - Cost of Goods import now processes in batches of 10 with 1 second delays
  - Prevents server overload during large imports
  - Maximum rate: 10 products per second
  - Ensures all products are imported without timeout errors
- **Backup Throttling** - Backup creation now processes in batches with delays
  - Processes 100 products at a time with 0.1 second delays between batches
  - Reduces server load during backup creation
  - Prevents memory issues with large product catalogs
- **Backup Retention** - Changed from 7 days to 2 days of backup retention
  - Reduces database size and storage overhead
  - Automatically deletes oldest backups when creating new ones
  - Keeps only the 2 most recent daily backups

### Technical
- Import batching: 10 products per batch with `sleep(1)` between batches
- Backup batching: 100 products per query with `usleep(100000)` between batches
- Updated `MAX_BACKUPS` constant from 7 to 2
- Backup version updated to 1.4.9

## [1.4.8] - 2024-12-01

### Added
- **WooCommerce Cost of Goods Import** - Migrate cost data from official WooCommerce Cost of Goods plugin
  - Automatic detection of Cost of Goods data (`_wc_cog_cost` meta key)
  - One-click import with automatic backup creation before import
  - Smart import: only imports non-zero values, updates if different, skips if already set
  - Shows detection panel with sample products and total count
  - Import results showing: new imports, updates, and skipped products
  - Preserves existing cost data (only updates if COG value is different)
  - Automatic inventory recalculation after import

### Technical
- New detection function: `detect_cost_of_goods_data()` checks for `_wc_cog_cost` meta
- New import function: `import_from_cost_of_goods()` handles migration with validation
- Admin action: `spvs_import_from_cog` with nonce protection
- Queries optimized to only process published products and variations
- Batch processing with delays every 200 products to avoid server overload

### References
- [WooCommerce Cost of Goods Documentation](https://woocommerce.com/document/cost-of-goods-sold/)
- Supports official WooCommerce Cost of Goods plugin meta key structure

## [1.4.7] - 2024-11-30

### Fixed
- **Gross Sales Calculation** - Now matches WooCommerce Analytics "Gross sales" metric
  - Changed from `$item->get_total()` (after discounts) to `$item->get_subtotal()` (before discounts)
  - Gross Sales = Sum of line item subtotals BEFORE discounts/coupons are applied
  - Verified against WooCommerce OrdersStatsDataStore source code on GitHub
  - Matches the exact "Gross sales" figure shown in WooCommerce Analytics Revenue report

### Technical
- Using `$item->get_subtotal()` instead of `$item->get_total()`
- Subtotal returns product price × quantity before any coupon discounts
- Referenced: [WooCommerce Admin DataStore.php](https://github.com/woocommerce/woocommerce-admin/blob/main/src/API/Reports/Orders/Stats/DataStore.php)

## [1.4.6] - 2024-11-30

### Fixed
- **Net Sales Calculation - Line Item Method** - Now uses exact WooCommerce Analytics methodology
  - Changed from Order Total - Tax - Shipping to summing product line items
  - `$item->get_total()` for each line item (products after discounts)
  - Excludes tax, shipping, and fees automatically
  - Matches WooCommerce Analytics Net Sales precisely

### Technical
- Loop through `$order->get_items()` and sum `$item->get_total()`
- This is identical to how WooCommerce Analytics calculates "Net Sales"
- Ensures revenue = Gross Sales - Coupons - Refunds (product sales only)

## [1.4.5] - 2024-11-30

### Fixed
- **Revenue Calculation - Net Sales** - Now uses exact same calculation as WooCommerce Analytics
  - Revenue = Order Total - Tax - Shipping (Net Sales)
  - This matches WooCommerce Analytics "Net Sales" metric precisely
  - Previously included tax and shipping which inflated numbers significantly

### Technical
- Changed revenue calculation from `$order->get_total()` to `$order->get_total() - $order->get_total_tax() - $order->get_shipping_total()`
- Aligns with WooCommerce's OrdersStatsDataStore net_total calculation

## [1.4.4] - 2024-11-30

### Fixed
- **Revenue Calculation Accuracy** - Revenue now matches WooCommerce Analytics exactly
  - Switched from raw SQL queries to WooCommerce's native `wc_get_orders()` API
  - Using `$order->get_total()` method which matches Analytics calculations
  - Ensures profit reports show identical revenue figures to WooCommerce reports

### Improved
- Better WooCommerce compatibility for order data retrieval
- More reliable profit calculations using official WooCommerce methods
- Consistent revenue reporting across all admin interfaces

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
