# WooCommerce Review Manager

A simple and powerful WordPress plugin that allows you to manually add and edit product reviews in WooCommerce.

## Features

- **Add Reviews Manually**: Add product reviews from external sources or manually create reviews for your products
- **Star Ratings**: Select from 1-5 star ratings for each review
- **Custom Review Dates**: Set custom dates for reviews when importing from other platforms
- **Flexible User Options**:
  - Select from existing WordPress users
  - Add custom reviewer names and emails for external reviews
- **Rich Text Editor**: Use WordPress's built-in editor to format review content
- **Edit Reviews**: Modify existing reviews including rating, content, and date
- **Delete Reviews**: Remove reviews with confirmation
- **Product Search**: Easily search and select products by name, SKU, or ID
- **User Search**: Search for existing users by username, email, or display name
- **Clean Interface**: Modern, user-friendly admin interface
- **AJAX-Powered**: Fast, seamless experience without page reloads

## Installation

1. Upload the `woocommerce-review-manager` folder to the `/wp-content/plugins/` directory
2. Activate the plugin through the 'Plugins' menu in WordPress
3. Navigate to 'Review Manager' in the WordPress admin menu

## Requirements

- WordPress 5.0 or higher
- WooCommerce 5.0 or higher
- PHP 7.2 or higher

## Usage

### Adding a New Review

1. Go to **Review Manager** in the WordPress admin menu
2. In the "Add New Review" section:
   - Select a product using the search field
   - Choose a star rating (1-5 stars)
   - Select user type:
     - **Existing User**: Search and select from WordPress users
     - **Custom Name/Email**: Enter a custom reviewer name and email
   - Enter the review text using the rich text editor
3. Click "Add Review"

### Managing Existing Reviews

1. In the "Manage Existing Reviews" section:
   - Select a product to view its reviews
   - Click "Load Reviews"
2. For each review you can:
   - **Edit**: Modify the rating and review text
   - **Delete**: Remove the review (with confirmation)

### Editing a Review

1. Click the "Edit" button on any review
2. In the modal dialog:
   - Update the star rating
   - Modify the review text
3. Click "Update Review"

## Features in Detail

### Star Rating System
- Visual star rating selector with 1-5 stars
- Stars display in both the add/edit forms and review listings
- Automatically updates product average rating and review count

### User Management
- **Existing Users**: Search by username, email, or display name
- **Custom Users**: Perfect for importing reviews from other platforms
- Maintains reviewer information accurately

### Product Search
- Search by product name
- Search by SKU
- Shows product ID for clarity
- Supports all product types

### Review Display
- Shows reviewer name and email
- Displays star rating
- Shows full review content
- Includes posting date
- Quick edit and delete actions

## Technical Details

- Uses WordPress AJAX for all operations
- Properly sanitizes and validates all inputs
- Updates WooCommerce product rating metadata
- Compatible with WooCommerce review system
- Responsive admin interface
- Select2 integration for enhanced dropdowns

## Changelog

### Version 1.1.0
- Added ability to set custom review dates when adding reviews
- Added ability to edit review dates
- Date field with datetime picker for easy date/time selection
- Perfect for importing reviews from other platforms with original dates

### Version 1.0.0
- Initial release
- Add product reviews manually
- Edit existing reviews
- Delete reviews
- Star rating system (1-5 stars)
- Support for existing users and custom names/emails
- Rich text editor for review content
- Product and user search functionality

## License

GPL v2 or later

## Author

SPVS - https://github.com/renthemighty

## Support

For issues and feature requests, please visit: https://github.com/renthemighty/Plugins
