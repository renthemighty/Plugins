# WooCommerce Top Spenders Export

A robust WordPress plugin that exports all customers with any purchase history from your WooCommerce store, sorted by total spend, with intelligent batch processing and rate limiting to prevent server overload.

## Features

- Export all customers with any purchase history, sorted by total spend
- **Batch processing** - Processes data in chunks of 100 customers to avoid memory issues
- **Rate limiting** - 1 second delay between batches to prevent server overload
- **Real-time progress indicator** - Visual progress bar with status updates
- **AJAX-powered** - Non-blocking export process
- CSV format with customer name, email, phone number, and total spend
- Statistics dashboard showing total customers, orders, and revenue
- Only includes completed and processing orders
- **Comprehensive error handling** - Graceful error recovery and user feedback
- **Data sanitization** - All customer data is properly sanitized
- **Transient-based caching** - Secure temporary storage during export
- Easy-to-use admin interface

## Requirements

- WordPress 5.0 or higher
- WooCommerce 5.0 or higher
- PHP 7.2 or higher
- MySQL 5.6 or higher / MariaDB 10.0 or higher

## Installation

1. Upload the `woocommerce-top-spenders` folder to the `/wp-content/plugins/` directory
2. Activate the plugin through the 'Plugins' menu in WordPress
3. Navigate to 'Top Spenders' in the WordPress admin menu

## Usage

1. Go to the 'Top Spenders' page in your WordPress admin
2. Click the "Export All Spenders" button
3. Monitor the progress bar as the export processes in batches of 100
4. Once complete, click "Download CSV File" to get your export
5. The CSV file will include the following columns:
   - Name (Customer's full name)
   - Email (Customer's email address)
   - Phone Number (Customer's phone number)
   - Total Spend (Total amount spent by the customer)

## How It Works

### Batch Processing
The plugin processes all customer data in batches of 100 to avoid overwhelming the server. Each batch is processed sequentially with a 1-second delay between batches to ensure optimal server performance.

### Rate Limiting
To prevent server overload and ensure compatibility with shared hosting environments, the plugin enforces a rate limit of 1 request per second. This means:
- For 1,000 customers: approximately 10 batches × 1 second = ~10 seconds total
- For 10,000 customers: approximately 100 batches × 1 second = ~100 seconds total
- Server load remains minimal throughout the process
- No risk of timeout errors on most hosting environments

### Data Storage
During the export process, data is temporarily stored in WordPress transients with a 1-hour expiration. This ensures:
- Data is cleared automatically if the export is interrupted
- Multiple admins can run exports simultaneously without conflicts
- No permanent database changes

## CSV Output

The exported CSV file includes:
- UTF-8 BOM for Excel compatibility
- All customers sorted by total spend (highest to lowest)
- Only customers with completed or processing orders
- Formatted currency values with 2 decimal places
- Timestamped filename (e.g., `top-spenders-2024-01-15-143022.csv`)

## Security Features

- Nonce verification on all AJAX requests
- Capability checks (`manage_woocommerce` permission required)
- Input sanitization and validation
- SQL injection prevention through prepared statements
- XSS protection through proper escaping

## Browser Compatibility

- Chrome/Edge (latest)
- Firefox (latest)
- Safari (latest)
- Requires JavaScript enabled

## Troubleshooting

### Export Session Expired
If you see this error, the export took longer than 1 hour or was interrupted. Simply start a new export.

### No Customers Found
This means there are no completed or processing orders in your WooCommerce store.

### Network Errors
Check your internet connection and ensure your WordPress admin is accessible.

## Performance Considerations

- Optimized database queries with proper indexing
- Batch processing prevents memory exhaustion
- Rate limiting prevents server throttling
- Transient cleanup prevents database bloat
- No impact on frontend performance

## Version History

### 1.2.0
- Export all customers with any purchase history (removed 500-customer cap)
- Increased batch size from 50 to 100 customers per request
- Updated UI text and documentation

### 1.1.0
- Added AJAX-based batch processing
- Implemented rate limiting (1 request per second)
- Added real-time progress indicator
- Improved error handling and user feedback
- Optimized database queries for better performance
- Added comprehensive data sanitization
- Added transient-based session management
- Added export cancellation feature
- Improved UI/UX with better visual feedback
- Added internationalization support

### 1.0.0
- Initial release
- Export top 500 spenders functionality
- Statistics dashboard

## License

GPL v2 or later
