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

### 2.4.0
- **FIXED: Only show notes on packing slips, not invoices**
- Use wcpdf_get_document() and get_type() for reliable document type checking
- Removed debug code for cleaner production version
- Properly filters to only packing-slip document type

### 2.3.0
- **FIXED: Exclude system-generated notes, only show manually-entered private notes**
- Added filter: user_id > 0 (manual notes) vs user_id = 0 (system notes)
- Now excludes: customer notes, system status changes, automated plugin notes
- Only shows: private notes manually typed by staff in the order page
- This is what users actually want - their own notes, not system messages

### 2.1.1
- **Add CSS to hide template's default notes display**
- Hide .document-notes, .order-notes, .customer-notes, .notes classes
- Prevents template from showing notes that we can't control
- Only our filtered private notes section will be visible
- Fixes issue where template was showing all notes in addition to our filtered notes

### 2.1.0
- **Direct database query approach for absolute reliability**
- Queries wp_comments and wp_commentmeta tables directly
- SQL query explicitly excludes notes where is_customer_note = '1'
- Bypasses all WooCommerce functions for maximum control
- Guaranteed to only return private notes

### 2.0.2
- **Use type='internal' parameter in wc_get_order_notes() for direct filtering**
- Simplified to let WooCommerce handle filtering at query level
- No manual filtering needed - WooCommerce returns only private notes
- type='internal' excludes all customer-facing notes

### 2.0.1
- **FIXED: Use wc_get_order_notes() function instead of $order->get_notes()**
- Fixed fatal error: Call to undefined method get_notes()
- Properly uses wc_get_order_notes() standalone function
- Filters notes by checking customer_note property (0/false = private, 1/true = customer)

### 2.0.0
- **COMPLETE REWRITE: Now uses WooCommerce Order object's get_notes() method**
- Uses WC_Order_Note objects with customer_note property for accurate filtering
- Checks empty($note->customer_note) to identify private notes
- Completely new approach that directly uses WooCommerce's native note system
- More reliable and future-proof

### 1.2.1
- **CORRECTLY FIXED: Uses meta_query to filter is_customer_note at database level**
- Confirmed WooCommerce uses 'is_customer_note' meta field (value = 1 for customer notes)
- Now filters using meta_query in get_comments() for reliable database-level filtering
- Excludes all notes where is_customer_note = 1

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
