# WooCommerce Simple Bundle v3.0.0

A professionally architected WooCommerce extension for creating bundle products with automatic stock management.

## What's New in v3.0.0

Complete rewrite from the ground up with the following improvements:

- **Simplified Architecture**: Removed all unnecessary hooks and complexity
- **Proper Product Type Handling**: WooCommerce now automatically recognizes and saves the bundle type
- **Clean Code**: Removed all debugging code and redundant functions
- **Better Performance**: Streamlined initialization and reduced hook usage

## How It Works

WooCommerce automatically handles product type saving when you:
1. Extend `WC_Product` properly
2. Set `product_type` in the constructor
3. Return the correct type from `get_type()`
4. Register the product class with the `woocommerce_product_class` filter

No manual intervention needed - WooCommerce does the heavy lifting!

## Features

### Core Functionality
- **Custom Product Type**: Adds "Bundle" to WooCommerce product types
- **Price Management**: Full support for regular price, sale price, and scheduled sales
- **Stock Management**: Automatic stock reduction/restoration for bundled products
- **Quantity Control**: Set specific quantities for each product in the bundle
- **Product Search**: AJAX-powered product search with autocomplete
- **Sortable Items**: Drag and drop to reorder products in bundle

## Installation

1. Upload the `wc-simple-bundle` folder to `/wp-content/plugins/`
2. Activate the plugin through the WordPress 'Plugins' menu
3. WooCommerce must be installed and active

## Usage

### Creating a Bundle

1. **Create New Product**
   - Go to Products → Add New
   - Enter product title and description

2. **Select Bundle Type**
   - In Product Data metabox, select "Bundle" from dropdown
   - The bundle will automatically save as a Bundle type

3. **Set Pricing**
   - Go to General tab
   - Enter Regular Price (required)
   - Optionally set Sale Price

4. **Add Products to Bundle**
   - Click "Bundle Products" tab
   - Type product name in search field (minimum 3 characters)
   - Select product from dropdown
   - Set quantity for each product (default: 1)
   - Add multiple products as needed

5. **Publish**
   - Click Publish button
   - Product will save as Bundle type automatically

### Stock Management

When a bundle is purchased:
- Each bundled product's stock is reduced by: `(quantity in bundle) × (bundles purchased)`
- Order notes are added documenting each stock change

When an order is cancelled/refunded:
- Stock is automatically restored
- Order notes document the restoration

## File Structure

```
wc-simple-bundle/
├── wc-simple-bundle.php          # Main plugin file
├── includes/
│   └── class-wc-product-bundle.php  # Bundle product class
├── views/
│   └── admin-bundle-panel.php    # Admin UI template
├── assets/
│   ├── admin.js                  # Admin JavaScript
│   └── admin.css                 # Admin styles
└── README.md                     # This file
```

## Requirements

- WordPress 5.8+
- PHP 7.4+
- WooCommerce 6.0+

## Changelog

### 3.0.0 - 2024-11-21
- Complete rewrite with simplified architecture
- Removed all manual product type saving - WooCommerce handles it automatically
- Removed debugging code
- Cleaner, more maintainable codebase
- Better adherence to WooCommerce standards

### 2.2.x
- Various attempts to manually handle product type saving
- Debug features

### 2.0.0
- Initial professional rewrite

## Technical Notes

### Why This Version Works

Previous versions tried to manually save the product type using various hooks like:
- `save_post`
- `save_post_product`
- `woocommerce_process_product_meta`
- `woocommerce_admin_process_product_object`

This caused conflicts because WooCommerce was also trying to save the product type.

**The solution:** Let WooCommerce do its job! When you properly:
1. Register the product class with `woocommerce_product_class` filter
2. Have a class that extends `WC_Product`
3. Set `product_type` in constructor
4. Return correct type from `get_type()`

WooCommerce automatically handles saving the product type correctly. No manual intervention needed!

## License

GPL v2 or later
