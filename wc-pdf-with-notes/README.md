# WooCommerce PDF Documents with Notes

Generate PDF invoices and packing slips with proper note filtering.

## Description

This plugin adds PDF invoice and packing slip generation to WooCommerce with intelligent note routing:

- **Private notes** (staff-entered, internal) appear on **packing slips**
- **Customer notes** (customer-facing) appear on **invoices**

## Key Features

- One-click PDF generation from orders page
- Opens PDFs in new window
- Works with "PDF Invoices & Packing Slips for WooCommerce" plugin
- Falls back to simple HTML/print if PDF plugin not installed
- Proper note filtering based on note type
- Clean, professional formatting

## Installation

1. Upload the plugin files to `/wp-content/plugins/wc-pdf-with-notes/`
2. Activate the plugin through the 'Plugins' menu in WordPress
3. (Optional) Install "PDF Invoices & Packing Slips for WooCommerce" for full PDF support

## Requirements

- WordPress 5.0 or higher
- WooCommerce 5.0 or higher
- PHP 7.2 or higher
- (Optional) PDF Invoices & Packing Slips for WooCommerce plugin for full PDF functionality

## Usage

1. Go to WooCommerce → Orders
2. Hover over any order
3. Click "Invoice" or "Packing Slip" action button
4. PDF will open in new window

### Note Types

**Private Notes (Packing Slip):**
- Notes entered by staff with "Private note" checkbox
- Internal notes not visible to customers
- Appear ONLY on packing slips

**Customer Notes (Invoice):**
- Notes entered with "Note to customer" checkbox
- Customer-facing notes
- Appear ONLY on invoices

## How It Works

### With PDF Plugin Installed:
- Integrates with "PDF Invoices & Packing Slips for WooCommerce"
- Uses existing PDF generation
- Adds proper note filtering via hooks

### Without PDF Plugin:
- Generates simple HTML document
- Opens in new window
- Can be printed to PDF using browser

## Changelog

### 1.0.0
- Initial release
- PDF generation with note filtering
- Packing slip and invoice buttons on orders page
- Private notes on packing slip
- Customer notes on invoice
- Integration with PDF Invoices & Packing Slips plugin

## License

GPL v2 or later
