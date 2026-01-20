# WooCommerce Top Spenders Export

A simple WordPress plugin that allows you to export the top 500 customers by total revenue from your WooCommerce store.

## Features

- Export top 500 customers by total spend
- CSV format with customer name, email, phone number, and total spend
- Statistics dashboard showing total customers, orders, and revenue
- Only includes completed and processing orders
- Easy-to-use admin interface

## Requirements

- WordPress 5.0 or higher
- WooCommerce 5.0 or higher
- PHP 7.2 or higher

## Installation

1. Upload the `woocommerce-top-spenders` folder to the `/wp-content/plugins/` directory
2. Activate the plugin through the 'Plugins' menu in WordPress
3. Navigate to 'Top Spenders' in the WordPress admin menu

## Usage

1. Go to the 'Top Spenders' page in your WordPress admin
2. Click the "Export Top 500 Spenders" button
3. A CSV file will be downloaded with the following columns:
   - Name (Customer's full name)
   - Email (Customer's email address)
   - Phone Number (Customer's phone number)
   - Total Spend (Total amount spent by the customer)

## CSV Output

The exported CSV file includes:
- UTF-8 BOM for Excel compatibility
- Top 500 customers sorted by total spend (highest to lowest)
- Only customers with completed or processing orders
- Formatted currency values

## Version History

### 1.0.0
- Initial release
- Export top 500 spenders functionality
- Statistics dashboard

## License

GPL v2 or later
