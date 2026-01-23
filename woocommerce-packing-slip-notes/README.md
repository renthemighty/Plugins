# WooCommerce Packing Slip Private Notes

Adds private (internal) order notes to WooCommerce packing slips automatically.

## Description

This plugin automatically displays private order notes on your WooCommerce packing slips. Perfect for warehouse staff and fulfillment teams who need to see internal notes when packing orders.

**Key Features:**

- Automatically adds private order notes to packing slips
- Only shows internal notes (customer notes are excluded)
- Compatible with "PDF Invoices & Packing Slips for WooCommerce" by WP Overnight
- Compatible with "WooCommerce Print Invoices/Packing Lists" plugin
- Configurable display options
- Clean, professional formatting
- Simple and straightforward - works out of the box

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

- **Enable Private Notes** - Turn the feature on/off
- **Notes Heading** - Customize the heading text (default: "Internal Notes")
- **Include Timestamps** - Show when each note was added
- **Include Author** - Show who added each note
- **Maximum Notes** - Limit how many notes to display (0 = unlimited)

## Usage

1. Add private notes to any WooCommerce order (do NOT check "Note to customer")
2. Generate a packing slip for the order
3. Private notes will automatically appear on the packing slip

**Important:** Only private/internal notes are displayed. Customer-facing notes are automatically excluded.

## Compatible Plugins

- PDF Invoices & Packing Slips for WooCommerce (by WP Overnight)
- WooCommerce Print Invoices/Packing Lists

## Support

For issues or feature requests, visit: https://github.com/renthemighty/Plugins

## Changelog

### 1.2.0
- **PROPERLY FIXED: Now checks order_note_type meta field correctly**
- Discovered WooCommerce uses 'order_note_type' meta, not 'is_customer_note'
- Private notes have empty order_note_type, customer notes have 'customer'
- Simplified code to directly filter by order_note_type meta field
- Removed wc_get_order_notes dependency for more reliable filtering

### 1.1.4
- **FIXED: Now correctly uses type='internal' parameter to get only private notes**
- Simplified note retrieval to use proper WooCommerce API
- Removes all manual filtering - WooCommerce handles it correctly

### 1.1.3
- Use WooCommerce native wc_get_order_notes() function for better compatibility
- Support for HPOS (High-Performance Order Storage)
- More reliable filtering of private vs customer notes

### 1.1.2
- Fixed filtering logic to properly exclude all customer notes
- Improved note type detection with explicit comparison

### 1.1.1
- Simplified to only show private notes (removed settings option)
- Fixed filtering to ensure only private/internal notes are displayed
- Reverted heading default to "Internal Notes"
- Improved code efficiency

### 1.0.0
- Initial release
- Support for WooCommerce PDF Invoices & Packing Slips
- Configurable display options
- Clean, professional note formatting

## License

GPL v2 or later
