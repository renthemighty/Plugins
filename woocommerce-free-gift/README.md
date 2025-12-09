# WooCommerce Free Gift

A lightweight WooCommerce plugin that automatically adds a free gift product to every order.

## Description

This plugin allows you to select a product from your WooCommerce store that will be automatically added to every customer's cart as a free gift. The product is always added at $0.00, regardless of its original price.

## Features

- **Simple Configuration**: Easy-to-use admin dashboard to select your free gift product
- **Automatic Addition**: Free gift is automatically added to every cart
- **Always Free**: Product is always $0.00, even if discount plugins are active
- **Plugin Compatibility**: Designed to work with sales and discount plugins
- **Lightweight**: Minimal code footprint for maximum performance
- **No Removal**: Customers cannot remove the free gift from their cart
- **Single Gift**: Only one free gift per order, regardless of cart size

## Installation

1. Upload the `woocommerce-free-gift` folder to the `/wp-content/plugins/` directory
2. Activate the plugin through the 'Plugins' menu in WordPress
3. Go to 'Free Gift' in the WordPress admin menu
4. Select the product you want to use as a free gift
5. Click 'Save Settings'

## Requirements

- WordPress 5.0 or higher
- WooCommerce 5.0 or higher
- PHP 7.2 or higher

## Usage

1. Navigate to **Free Gift** in your WordPress admin menu
2. Select a product from the dropdown list
3. Click **Save Settings**
4. The selected product will now be automatically added to every cart

## How It Works

- The selected product is automatically added to every customer's cart
- The product is always added at $0.00 (free)
- Works with discount and sales plugins - the free gift stays free
- Customers cannot remove the free gift from their cart
- Only one free gift is added per order, regardless of cart contents

## Compatibility

This plugin is designed to be compatible with:
- All WooCommerce themes
- Discount plugins
- Sales plugins
- Coupon plugins
- Other cart modification plugins

The plugin uses late-priority hooks (priority 999) to ensure it runs after most other plugins, maintaining the free price even if other plugins try to modify it.

## Frequently Asked Questions

### Can customers remove the free gift?
No, the free gift is automatically added and cannot be removed by customers.

### Will this work with discount plugins?
Yes, the plugin is designed to work with discount and sales plugins. The free gift will always remain at $0.00.

### Can I select multiple free gifts?
Currently, the plugin supports one free gift product at a time.

### Does the free gift affect shipping?
This depends on your product settings. If the free gift product has weight/dimensions, it will be included in shipping calculations. You can set the product to "Virtual" to exclude it from shipping.

### What happens if I deactivate the plugin?
The free gift will no longer be added to carts. Existing carts will not be affected until they are updated.

## Changelog

### 1.0.0
- Initial release
- Basic free gift functionality
- Admin settings page
- Product selector dropdown
- Compatibility with discount plugins

## Support

For issues, questions, or feature requests, please visit:
https://github.com/renthemighty/Plugins/issues

## License

GPL v2 or later
https://www.gnu.org/licenses/gpl-2.0.html

## Author

SPVS
https://github.com/renthemighty
