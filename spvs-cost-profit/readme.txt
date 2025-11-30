=== SPVS Cost & Profit for WooCommerce ===
Contributors: megatron
Tags: woocommerce, profit, cost, inventory, reports
Requires at least: 6.0
Tested up to: 6.4
Requires PHP: 7.4
Stable tag: 1.4.0
License: GPL-2.0+
License URI: https://www.gnu.org/licenses/gpl-2.0.txt

Add product costs, calculate profit per order, track inventory value (TCOP/Retail), and view monthly profit reports with CSV export/import.

== Description ==

SPVS Cost & Profit for WooCommerce is a comprehensive plugin that helps you track costs, calculate profits, and manage inventory value for your WooCommerce store.

= Key Features =

* **Product Cost Tracking**: Add cost prices to products and variations
* **Automatic Profit Calculation**: Profit is calculated automatically for each order (Revenue - Cost)
* **Order Profit Display**: View profit for each order in the orders list and order details
* **Inventory Value Reports**: Track Total Cost of Products (TCOP) and Retail value of your inventory
* **Monthly Profit Reports**: Visualize profit trends with interactive charts and detailed monthly breakdowns
* **CSV Import/Export**: Bulk import costs and export inventory data
* **HPOS Compatible**: Fully compatible with WooCommerce High-Performance Order Storage
* **Variation Support**: Cost inheritance from parent products when variations don't have costs set
* **Daily Auto-Calculation**: Inventory totals recalculate automatically via daily cron job

= What This Plugin Does =

1. **Product Management**:
   - Add a "Cost Price" field to all products and variations
   - Variations inherit parent cost if no specific cost is set
   - Track cost at the time of sale for accurate historical profit

2. **Order Profit Tracking**:
   - Automatically calculates profit when orders are placed
   - Displays profit column in orders list
   - Shows profit meta box on order detail page
   - Accounts for refunds in profit calculations
   - Sortable profit column for easy analysis

3. **Inventory Value Management**:
   - Calculates Total Cost of Products (TCOP) for items in stock
   - Calculates total Retail value based on regular prices
   - Shows spread (potential profit margin) on inventory
   - Quick recalculation with one click
   - Displays summary bar on orders screen

4. **Monthly Profit Reports**:
   - Interactive charts showing profit and revenue trends
   - Monthly breakdown with order count, revenue, profit, and margins
   - Customizable date range selection
   - CSV export for further analysis
   - Average profit per order calculations

5. **CSV Operations**:
   - Import costs in bulk using SKU, Product ID, or Slug
   - Export complete inventory with customizable columns
   - Download template for easy import
   - Export items with missing costs for quick review
   - Download unmatched rows from imports for troubleshooting

= Use Cases =

* **E-commerce Businesses**: Track real profitability of your online store
* **Wholesalers**: Manage inventory value and profit margins
* **Dropshippers**: Monitor per-order profits including supplier costs
* **Multi-channel Sellers**: Understand true profit after all costs
* **Accountants**: Export detailed reports for financial analysis

= Privacy & Data =

This plugin stores cost and profit data locally in your WordPress database. No data is sent to external services. All calculations are performed on your server.

== Installation ==

1. Upload the plugin files to `/wp-content/plugins/spvs-cost-profit/` directory, or install through WordPress plugins screen
2. Activate the plugin through the 'Plugins' screen in WordPress
3. Ensure WooCommerce is installed and activated
4. Go to WooCommerce > SPVS Inventory to configure and view inventory values
5. Go to WooCommerce > SPVS Profit Reports to view monthly profit analysis
6. Edit any product to add cost prices in the "General" or "Variations" tab

== Frequently Asked Questions ==

= Does this work with variable products? =

Yes! You can set costs for each variation individually. If a variation doesn't have a cost set, it will automatically use the parent product's cost.

= Is this compatible with HPOS (High-Performance Order Storage)? =

Yes, the plugin is fully compatible with WooCommerce HPOS and declares compatibility accordingly.

= How is profit calculated? =

Profit = Order Line Total (excluding tax) - (Unit Cost × Quantity)

The calculation is performed at checkout and stored with the order. Refunds are reflected in the line totals.

= Can I import costs in bulk? =

Yes! Go to WooCommerce > SPVS Inventory and use the CSV import feature. You can match products by SKU, Product ID, or Slug.

= What columns can I export? =

You can export any combination of these columns:
- Product ID, Parent ID, Type, Status
- SKU, Name, Attributes, Categories, Tags
- Stock management fields (Manage stock, Stock status, Quantity, Backorders)
- Pricing (Cost, Regular price, Sale price, Current price)
- Calculated totals (Cost × Qty, Regular × Qty)
- Dimensions, Weight, Tax class
- Dates (Created, Modified)

= When are inventory totals calculated? =

Inventory totals (TCOP and Retail) are automatically recalculated daily at 2:30 AM via WordPress cron. You can also trigger manual recalculation anytime.

= What order statuses are included in profit reports? =

By default, only "Completed" and "Processing" orders are included in profit reports. This can be customized using the `spvs_profit_report_order_statuses` filter.

= Will this affect my site performance? =

No. The plugin uses efficient batch processing with throttling for large inventories. Calculations are cached and updated via background cron jobs.

= Can I customize which order statuses count toward profit? =

Yes, use the filter `spvs_profit_report_order_statuses` to customize which statuses are included in reports.

= Does uninstalling remove all data? =

Yes. When you uninstall (not just deactivate) the plugin, all cost data, profit calculations, and settings are completely removed from your database.

== Screenshots ==

1. Product cost field in product editor
2. Variation cost fields
3. Profit column in orders list
4. Profit meta box on order detail page
5. TCOP bar on orders screen
6. Inventory value page with import/export
7. Monthly profit reports with charts
8. CSV export options

== Changelog ==

= 1.4.0 - 2024-11-30 =
* Added: Monthly profit reports with interactive charts
* Added: Profit trends visualization using Chart.js
* Added: Customizable date range for reports
* Added: Monthly CSV export with margin calculations
* Added: Revenue vs profit comparison charts
* Added: Average profit per order metrics
* Improved: Admin menu structure with separate report page
* Improved: Better compatibility with WooCommerce HPOS

= 1.3.0 =
* Added: CSV export for items with missing costs
* Added: Download unmatched rows from imports
* Added: Cost template CSV download
* Improved: Import matching by SKU, Product ID, and Slug
* Improved: Better error handling in imports

= 1.2.0 =
* Added: Inventory value calculations (TCOP/Retail)
* Added: TCOP summary bar on orders screen
* Added: Daily automatic recalculation via cron
* Added: CSV export/import for costs
* Added: Customizable column selection for exports

= 1.1.0 =
* Added: Profit column to orders list
* Added: Sortable profit column
* Added: HPOS compatibility declaration
* Improved: Order profit recalculation on refunds

= 1.0.0 =
* Initial release
* Product cost field for simple and variable products
* Automatic profit calculation on checkout
* Profit display on order details

== Upgrade Notice ==

= 1.4.0 =
New monthly profit reports feature with interactive charts! View profit trends and export detailed monthly analysis.

= 1.3.0 =
Improved CSV import/export features with better product matching and error handling.

= 1.2.0 =
Major update with inventory value tracking (TCOP/Retail) and automated daily calculations.

== Additional Information ==

= Support =

For support, feature requests, or bug reports, please use the WordPress.org support forums.

= Contributing =

This plugin is open source. Contributions and suggestions are welcome!

= Filters & Hooks =

**Filters:**
- `spvs_inventory_available_columns` - Customize available export columns
- `spvs_inventory_csv_value_{column}` - Modify column values in exports
- `spvs_profit_report_order_statuses` - Customize which order statuses count toward profit

**Actions:**
Available throughout the plugin for extending functionality.

= Database Schema =

**Product Meta:**
- `_spvs_cost_price` - Unit cost price
- `_spvs_stock_cost_total` - Total cost for items in stock (cached)
- `_spvs_stock_retail_total` - Total retail value (cached)

**Order Meta:**
- `_spvs_total_profit` - Total profit for the order

**Order Item Meta:**
- `_spvs_line_profit` - Profit for the line item
- `_spvs_unit_cost` - Unit cost at time of sale

**Options:**
- `spvs_inventory_totals_cache` - Cached inventory totals (TCOP, Retail, etc.)

All data is removed on uninstall.
