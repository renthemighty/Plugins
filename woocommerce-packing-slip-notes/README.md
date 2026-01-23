# WooCommerce Packing Slip Notes

Adds order notes (private, public, or both) to WooCommerce packing slips automatically.

## Description

This plugin automatically displays order notes on your WooCommerce packing slips. Perfect for warehouse staff and fulfillment teams who need to see notes when packing orders.

**Key Features:**

- Automatically adds order notes to packing slips
- Choose between private notes, public notes, or both
- Compatible with "PDF Invoices & Packing Slips for WooCommerce" by WP Overnight
- Compatible with "WooCommerce Print Invoices/Packing Lists" plugin
- Configurable display options
- Clean, professional formatting
- Smart note filtering based on your preferences

## Installation

1. Upload the plugin files to `/wp-content/plugins/woocommerce-packing-slip-notes/`
2. Activate the plugin through the 'Plugins' menu in WordPress
3. Configure settings at WooCommerce → Settings → Advanced → Packing Slip Notes

## Requirements

- WordPress 5.0 or higher
- WooCommerce 5.0 or higher
- PHP 7.2 or higher
- A packing slip plugin (recommended: "PDF Invoices & Packing Slips for WooCommerce")

## Configuration

Navigate to **WooCommerce → Settings → Advanced → Packing Slip Notes**

### Settings Options:

- **Enable Notes** - Turn the feature on/off
- **Note Type** - Choose which notes to display:
  - **Private notes only** (default) - Shows only internal notes not visible to customers
  - **Public/customer notes only** - Shows only customer-facing notes
  - **Both private and public notes** - Shows all order notes
- **Notes Heading** - Customize the heading text (default: "Order Notes")
- **Include Timestamps** - Show when each note was added
- **Include Author** - Show who added each note
- **Maximum Notes** - Limit how many notes to display (0 = unlimited)

## Usage

1. Configure which type of notes to display (WooCommerce → Settings → Advanced → Packing Slip Notes)
2. Add notes to any WooCommerce order
   - For private notes: Leave "Private note" unchecked or use the internal note option
   - For public notes: Check "Note to customer"
3. Generate a packing slip for the order
4. Notes will automatically appear based on your settings

**Default Behavior:** By default, only private/internal notes are displayed (not customer-facing notes).

## Compatible Plugins

- PDF Invoices & Packing Slips for WooCommerce (by WP Overnight)
- WooCommerce Print Invoices/Packing Lists

## Support

For issues or feature requests, visit: https://github.com/renthemighty/Plugins

## Changelog

### 1.1.0
- Added option to choose note type: private only, public only, or both
- Improved note filtering logic
- Updated plugin name and descriptions
- Changed default heading to "Order Notes"

### 1.0.0
- Initial release
- Support for WooCommerce PDF Invoices & Packing Slips
- Configurable display options
- Clean, professional note formatting

## License

GPL v2 or later
