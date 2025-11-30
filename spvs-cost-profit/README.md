# SPVS Cost & Profit for WooCommerce

![Version](https://img.shields.io/badge/version-1.4.0-blue.svg)
![WordPress](https://img.shields.io/badge/WordPress-6.0%2B-blue.svg)
![WooCommerce](https://img.shields.io/badge/WooCommerce-7.0%2B-purple.svg)
![PHP](https://img.shields.io/badge/PHP-7.4%2B-777BB4.svg)
![License](https://img.shields.io/badge/license-GPL--2.0%2B-green.svg)

A comprehensive WooCommerce plugin for tracking product costs, calculating order profits, managing inventory value, and analyzing monthly profit trends.

## Features

### 🏷️ Product Cost Management
- Add cost prices to simple products and variations
- Variation cost inheritance from parent products
- Historical cost tracking at time of sale

### 💰 Profit Calculation
- Automatic profit calculation for all orders
- Real-time profit display in orders list
- Detailed profit breakdown on order pages
- Refund-aware profit calculations
- Sortable profit column for easy analysis

### 📊 Inventory Value Tracking
- **TCOP** (Total Cost of Products) calculation
- **Retail Value** based on regular prices
- **Spread** (potential profit margin) display
- Quick recalculation with one click
- Summary bar on orders screen
- Daily automated recalculation

### 📈 Monthly Profit Reports *(New in v1.4.0)*
- Interactive charts powered by Chart.js
- Monthly breakdown of profit and revenue
- Customizable date range selection
- Profit margin calculations
- Average profit per order
- CSV export for further analysis

### 📥📤 CSV Import/Export
- **Bulk Cost Import**: Match by SKU, Product ID, or Slug
- **Customizable Exports**: Choose which columns to include
- **Missing Cost Report**: Export items with quantity but no cost
- **Import Diagnostics**: Download unmatched rows for troubleshooting
- **Template Download**: Get started quickly with CSV template

### ⚡ Performance & Compatibility
- **HPOS Compatible**: Full support for WooCommerce High-Performance Order Storage
- **Efficient Processing**: Batch processing with throttling for large inventories
- **Cached Calculations**: Minimize database queries
- **Background Processing**: Daily cron jobs for inventory updates

## Installation

### From WordPress Admin

1. Download the latest release ZIP file
2. Go to **Plugins > Add New > Upload Plugin**
3. Choose the ZIP file and click **Install Now**
4. Click **Activate Plugin**
5. Ensure WooCommerce is installed and activated

### Manual Installation

1. Upload the `spvs-cost-profit` folder to `/wp-content/plugins/`
2. Activate through the **Plugins** menu in WordPress
3. Navigate to **WooCommerce > SPVS Inventory** or **SPVS Profit Reports**

### Requirements

- WordPress 6.0 or higher
- WooCommerce 7.0 or higher
- PHP 7.4 or higher

## Usage

### Adding Product Costs

1. Edit any product in WooCommerce
2. Find the **Cost Price** field in the **General** tab
3. For variations, set individual costs in the **Variations** tab
4. Save the product

### Viewing Profit Data

**On Orders List:**
- Profit column appears next to order total
- Click column header to sort by profit

**On Order Details:**
- Profit meta box appears in the sidebar
- Shows total profit for the order

**TCOP Bar:**
- Appears at the top of the orders screen
- Shows TCOP, Retail, and Spread values
- One-click recalculation button

### Monthly Profit Reports

1. Go to **WooCommerce > SPVS Profit Reports**
2. Select date range (defaults to last 12 months)
3. View interactive charts and detailed table
4. Export to CSV for further analysis

**Report Metrics:**
- Total Profit & Revenue
- Average Margin %
- Orders per month
- Profit per month
- Revenue per month
- Average profit per order

### Inventory Management

1. Go to **WooCommerce > SPVS Inventory**
2. View TCOP, Retail value, and Spread
3. Select columns for export/preview
4. Export inventory to CSV

### Bulk Cost Import

1. Download the cost template CSV
2. Fill in SKU/Product ID and Cost columns
3. Go to **WooCommerce > SPVS Inventory**
4. Upload your CSV file
5. Optionally check "Recalculate totals after import"
6. Click **Import Costs**

**CSV Format:**
```csv
sku,product_id,cost
ABC123,,15.50
,456,22.00
```

Match products by:
- `sku` - Product SKU
- `product_id` or `variation_id` - WordPress post ID
- `slug` - Product slug (parent products only)

### Customizable Export Columns

Choose from 20+ columns including:
- Product details (ID, SKU, Name, Type, Status)
- Attributes, Categories, Tags
- Stock information
- Cost and pricing data
- Calculated totals (Cost × Qty, Regular × Qty)
- Dimensions and weight
- Creation and modification dates

## How Profit is Calculated

```
Profit = Order Line Total (ex tax) - (Unit Cost × Quantity)
```

- **Revenue**: Line total excluding tax (including discounts, before tax)
- **Cost**: Unit cost at time of order × quantity
- **Refunds**: Reflected in line totals automatically

## Filters & Hooks

### Filters

```php
// Customize available export columns
add_filter( 'spvs_inventory_available_columns', function( $columns ) {
    $columns['custom_field'] = 'Custom Field';
    return $columns;
} );

// Modify column values in exports
add_filter( 'spvs_inventory_csv_value_custom_field', function( $value, $product, $product_id ) {
    return get_post_meta( $product_id, '_custom_field', true );
}, 10, 3 );

// Customize which order statuses count toward profit reports
add_filter( 'spvs_profit_report_order_statuses', function( $statuses ) {
    $statuses[] = 'wc-on-hold';
    return $statuses;
} );
```

## Database Schema

### Product Meta
- `_spvs_cost_price` - Unit cost price
- `_spvs_stock_cost_total` - Total cost for items in stock (cached)
- `_spvs_stock_retail_total` - Total retail value (cached)

### Order Meta
- `_spvs_total_profit` - Total profit for the order

### Order Item Meta
- `_spvs_line_profit` - Profit for the line item
- `_spvs_unit_cost` - Unit cost at time of sale

### Options
- `spvs_inventory_totals_cache` - Cached inventory totals

### Scheduled Events
- `spvs_daily_inventory_recalc` - Daily at 2:30 AM

**Note:** All data is completely removed when plugin is uninstalled.

## Screenshots

### Monthly Profit Reports
Interactive charts show profit and revenue trends over time.

### TCOP Bar
Quick summary of inventory value right on the orders screen.

### Product Cost Field
Easy-to-use cost field integrated into WooCommerce product editor.

### Orders List with Profit
See profit for each order at a glance with sortable column.

## Frequently Asked Questions

**Q: Does this work with variable products?**
A: Yes! Set costs per variation or let variations inherit from parent.

**Q: Is this compatible with HPOS?**
A: Yes, fully compatible with WooCommerce High-Performance Order Storage.

**Q: Will my existing orders show profit?**
A: Orders placed after activation will automatically calculate profit. For existing orders, profit will be calculated on-demand when viewed.

**Q: Can I export my data?**
A: Yes! Export inventory to CSV with customizable columns, and export monthly profit reports.

**Q: How often are inventory totals updated?**
A: Automatically every day at 2:30 AM, plus you can manually recalculate anytime.

**Q: What happens when I uninstall?**
A: All plugin data (costs, profits, caches) is completely removed from your database.

## Changelog

### 1.4.0 - 2024-11-30
- ✨ **New:** Monthly profit reports with interactive charts
- ✨ **New:** Profit trends visualization using Chart.js
- ✨ **New:** Customizable date range for reports
- ✨ **New:** Monthly CSV export with margin calculations
- ✨ **New:** Revenue vs profit comparison charts
- ✨ **New:** Average profit per order metrics
- 🔧 **Improved:** Admin menu structure with separate report page
- 🔧 **Improved:** Better compatibility with WooCommerce HPOS

### 1.3.0
- ✨ **New:** CSV export for items with missing costs
- ✨ **New:** Download unmatched rows from imports
- ✨ **New:** Cost template CSV download
- 🔧 **Improved:** Import matching by SKU, Product ID, and Slug
- 🔧 **Improved:** Better error handling in imports

### 1.2.0
- ✨ **New:** Inventory value calculations (TCOP/Retail)
- ✨ **New:** TCOP summary bar on orders screen
- ✨ **New:** Daily automatic recalculation via cron
- ✨ **New:** CSV export/import for costs
- ✨ **New:** Customizable column selection for exports

### 1.1.0
- ✨ **New:** Profit column to orders list
- ✨ **New:** Sortable profit column
- ✨ **New:** HPOS compatibility declaration
- 🔧 **Improved:** Order profit recalculation on refunds

### 1.0.0
- 🎉 Initial release

## Upgrade Guide

### To 1.4.0
No database changes required. The new monthly profit reports feature will work immediately with your existing order data.

### From 1.x to 1.4.0
Simply install and activate. All existing data is preserved. New features are available immediately.

## Support

For bug reports, feature requests, or support questions:

1. Check the [FAQ section](#frequently-asked-questions)
2. Search [existing issues](https://github.com/renthemighty/Plugins/issues)
3. [Open a new issue](https://github.com/renthemighty/Plugins/issues/new) if needed

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This plugin is licensed under the GPL-2.0+ License. See the [LICENSE](LICENSE) file for details.

## Credits

**Author:** Megatron
**Version:** 1.4.0
**Requires:** WordPress 6.0+, WooCommerce 7.0+, PHP 7.4+

---

Made with ❤️ for the WooCommerce community
