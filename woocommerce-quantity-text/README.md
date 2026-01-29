# WooCommerce Quantity Text

Adds custom text immediately above the quantity selector on WooCommerce product pages, configurable per product category.

## Description

Assign a short text label to any WooCommerce product category and it will appear directly above the quantity input on single product pages and anywhere the quantity selector is rendered. Useful for communicating unit-of-sale information such as "Pack of 10", "Sold by the pound", or "Sold individually".

## Features

- Map any product category to a custom text string
- Text displays immediately above the quantity input field
- Admin UI under **WooCommerce > Quantity Text**
- All mappings stored in a single autoloaded `wp_options` row — zero extra queries per page load
- Add, edit, and remove rules without page reloads (AJAX save)
- First matching category wins when a product belongs to multiple categories

## Installation

1. Upload the `woocommerce-quantity-text` folder to `/wp-content/plugins/`
2. Activate the plugin through **Plugins > Installed Plugins**
3. Navigate to **WooCommerce > Quantity Text** to configure category rules

## Requirements

- WordPress 5.0+
- WooCommerce 5.0+
- PHP 7.2+

## Usage

1. Go to **WooCommerce > Quantity Text** in your WordPress admin
2. Click **+ Add Rule**
3. Select a product category from the dropdown
4. Enter the text you want displayed (e.g. "Pack of 10")
5. Click **Save Changes**
6. Repeat for as many categories as needed

The text will appear above the quantity selector on any product that belongs to a configured category.

## Database Design

All category-to-text mappings are stored in a **single** `wp_options` row with autoload enabled. This means:

- **0 extra database queries** on page loads (WordPress autoloads the option on every request)
- The data is a simple associative array: `{ term_id: "display text", ... }`
- Reads are served from the WordPress object cache after the first load

## Changelog

### 1.0.0
- Initial release
- Admin page with dynamic rule management
- Frontend display on quantity selector
- Single autoloaded option for optimal performance

## License

GPL v2 or later

## Author

[Megatron](https://github.com/renthemighty)
