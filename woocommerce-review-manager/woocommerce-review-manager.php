<?php
/**
 * Plugin Name: WooCommerce Review Manager
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Manually add and edit product reviews with custom users and star ratings
 * Version: 1.1.0
 * Author: SPVS
 * Author URI: https://github.com/renthemighty
 * Requires at least: 5.0
 * Tested up to: 6.4
 * Requires PHP: 7.2
 * WC requires at least: 5.0
 * WC tested up to: 8.5
 * License: GPL v2 or later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: wc-review-manager
 */

defined('ABSPATH') || exit;

class WC_Review_Manager {

    private static $instance = null;

    public static function instance() {
        if (null === self::$instance) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        // Admin menu
        add_action('admin_menu', [$this, 'admin_menu']);
        add_action('admin_enqueue_scripts', [$this, 'admin_scripts']);

        // AJAX handlers
        add_action('wp_ajax_wcrm_search_products', [$this, 'ajax_search_products']);
        add_action('wp_ajax_wcrm_search_users', [$this, 'ajax_search_users']);
        add_action('wp_ajax_wcrm_add_review', [$this, 'ajax_add_review']);
        add_action('wp_ajax_wcrm_edit_review', [$this, 'ajax_edit_review']);
        add_action('wp_ajax_wcrm_delete_review', [$this, 'ajax_delete_review']);
        add_action('wp_ajax_wcrm_get_review', [$this, 'ajax_get_review']);
        add_action('wp_ajax_wcrm_list_reviews', [$this, 'ajax_list_reviews']);
    }

    public function admin_menu() {
        add_menu_page(
            'Review Manager',
            'Review Manager',
            'manage_options',
            'wc-review-manager',
            [$this, 'main_page'],
            'dashicons-star-filled',
            56
        );
    }

    public function admin_scripts($hook) {
        if ('toplevel_page_wc-review-manager' !== $hook) return;

        wp_enqueue_script('jquery');
        wp_enqueue_script('selectWoo');
        wp_enqueue_style('woocommerce_admin_styles');

        wp_enqueue_style('wcrm-styles', plugin_dir_url(__FILE__) . 'assets/style.css', [], '1.0.0');
        wp_enqueue_script('wcrm-script', plugin_dir_url(__FILE__) . 'assets/script.js', ['jquery', 'selectWoo'], '1.0.0', true);

        wp_localize_script('wcrm-script', 'wcrmData', [
            'ajaxurl' => admin_url('admin-ajax.php'),
            'nonce' => wp_create_nonce('wcrm-nonce')
        ]);
    }

    public function ajax_search_products() {
        check_ajax_referer('wcrm-nonce', 'security');

        $term = sanitize_text_field($_GET['term'] ?? '');
        $results = [];

        if (strlen($term) < 1) {
            wp_send_json($results);
        }

        // Search products by name or SKU
        $args = [
            'post_type' => 'product',
            'posts_per_page' => 50,
            's' => $term,
            'post_status' => 'publish'
        ];

        $sku_query = new WP_Query([
            'post_type' => 'product',
            'posts_per_page' => 50,
            'post_status' => 'publish',
            'meta_query' => [
                [
                    'key' => '_sku',
                    'value' => $term,
                    'compare' => 'LIKE'
                ]
            ]
        ]);

        $query = new WP_Query($args);
        $product_ids = array_merge($query->posts, $sku_query->posts);
        $product_ids = array_unique(array_map(function($post) { return $post->ID; }, $product_ids));

        foreach ($product_ids as $product_id) {
            $product = wc_get_product($product_id);
            if ($product) {
                $sku = $product->get_sku();
                $name = $product->get_name();
                $display_name = $name;
                if ($sku) {
                    $display_name = $name . ' (SKU: ' . $sku . ')';
                }
                $display_name .= ' (ID: ' . $product_id . ')';
                $results[$product_id] = $display_name;
            }
        }

        wp_send_json($results);
    }

    public function ajax_search_users() {
        check_ajax_referer('wcrm-nonce', 'security');

        $term = sanitize_text_field($_GET['term'] ?? '');
        $results = [];

        if (strlen($term) < 1) {
            wp_send_json($results);
        }

        $users = get_users([
            'search' => '*' . $term . '*',
            'search_columns' => ['user_login', 'user_email', 'display_name'],
            'number' => 50
        ]);

        foreach ($users as $user) {
            $results[$user->ID] = $user->display_name . ' (' . $user->user_email . ')';
        }

        wp_send_json($results);
    }

    public function ajax_add_review() {
        check_ajax_referer('wcrm-nonce', 'security');

        $product_id = absint($_POST['product_id'] ?? 0);
        $rating = absint($_POST['rating'] ?? 0);
        $review_text = wp_kses_post($_POST['review_text'] ?? '');
        $user_type = sanitize_text_field($_POST['user_type'] ?? 'existing');
        $user_id = absint($_POST['user_id'] ?? 0);
        $custom_name = sanitize_text_field($_POST['custom_name'] ?? '');
        $custom_email = sanitize_email($_POST['custom_email'] ?? '');
        $review_date = sanitize_text_field($_POST['review_date'] ?? '');

        // Validation
        if ($product_id <= 0) {
            wp_send_json_error('Please select a product');
        }

        if ($rating < 1 || $rating > 5) {
            wp_send_json_error('Please select a star rating (1-5)');
        }

        if (empty($review_text)) {
            wp_send_json_error('Please enter review text');
        }

        if ($user_type === 'existing' && $user_id <= 0) {
            wp_send_json_error('Please select a user');
        }

        if ($user_type === 'custom' && empty($custom_name)) {
            wp_send_json_error('Please enter a custom name');
        }

        if ($user_type === 'custom' && empty($custom_email)) {
            wp_send_json_error('Please enter a custom email');
        }

        // Prepare comment data
        $comment_author = '';
        $comment_author_email = '';
        $comment_user_id = 0;

        if ($user_type === 'existing') {
            $user = get_user_by('id', $user_id);
            if (!$user) {
                wp_send_json_error('Invalid user selected');
            }
            $comment_author = $user->display_name;
            $comment_author_email = $user->user_email;
            $comment_user_id = $user->ID;
        } else {
            $comment_author = $custom_name;
            $comment_author_email = $custom_email;
            $comment_user_id = 0;
        }

        // Handle review date
        $comment_date = current_time('mysql');
        $comment_date_gmt = current_time('mysql', 1);

        if (!empty($review_date)) {
            // Validate and convert the date
            $date_timestamp = strtotime($review_date);
            if ($date_timestamp !== false) {
                $comment_date = date('Y-m-d H:i:s', $date_timestamp);
                $comment_date_gmt = gmdate('Y-m-d H:i:s', $date_timestamp);
            }
        }

        // Insert comment (review)
        $comment_data = [
            'comment_post_ID' => $product_id,
            'comment_author' => $comment_author,
            'comment_author_email' => $comment_author_email,
            'comment_content' => $review_text,
            'comment_type' => 'review',
            'comment_parent' => 0,
            'user_id' => $comment_user_id,
            'comment_approved' => 1,
            'comment_date' => $comment_date,
            'comment_date_gmt' => $comment_date_gmt
        ];

        $comment_id = wp_insert_comment($comment_data);

        if (!$comment_id) {
            wp_send_json_error('Failed to add review');
        }

        // Add rating meta
        update_comment_meta($comment_id, 'rating', $rating);

        // Update product rating count and average
        $this->update_product_rating($product_id);

        wp_send_json_success([
            'message' => 'Review added successfully!',
            'comment_id' => $comment_id
        ]);
    }

    public function ajax_edit_review() {
        check_ajax_referer('wcrm-nonce', 'security');

        $comment_id = absint($_POST['comment_id'] ?? 0);
        $rating = absint($_POST['rating'] ?? 0);
        $review_text = wp_kses_post($_POST['review_text'] ?? '');
        $review_date = sanitize_text_field($_POST['review_date'] ?? '');

        // Validation
        if ($comment_id <= 0) {
            wp_send_json_error('Invalid review ID');
        }

        $comment = get_comment($comment_id);
        if (!$comment) {
            wp_send_json_error('Review not found');
        }

        if ($rating < 1 || $rating > 5) {
            wp_send_json_error('Please select a star rating (1-5)');
        }

        if (empty($review_text)) {
            wp_send_json_error('Please enter review text');
        }

        // Prepare update data
        $update_data = [
            'comment_ID' => $comment_id,
            'comment_content' => $review_text
        ];

        // Handle review date if provided
        if (!empty($review_date)) {
            $date_timestamp = strtotime($review_date);
            if ($date_timestamp !== false) {
                $update_data['comment_date'] = date('Y-m-d H:i:s', $date_timestamp);
                $update_data['comment_date_gmt'] = gmdate('Y-m-d H:i:s', $date_timestamp);
            }
        }

        // Update comment
        $result = wp_update_comment($update_data);

        if ($result === false) {
            wp_send_json_error('Failed to update review');
        }

        // Update rating meta
        update_comment_meta($comment_id, 'rating', $rating);

        // Update product rating
        $this->update_product_rating($comment->comment_post_ID);

        wp_send_json_success([
            'message' => 'Review updated successfully!'
        ]);
    }

    public function ajax_delete_review() {
        check_ajax_referer('wcrm-nonce', 'security');

        $comment_id = absint($_POST['comment_id'] ?? 0);

        if ($comment_id <= 0) {
            wp_send_json_error('Invalid review ID');
        }

        $comment = get_comment($comment_id);
        if (!$comment) {
            wp_send_json_error('Review not found');
        }

        $product_id = $comment->comment_post_ID;

        // Delete comment
        $result = wp_delete_comment($comment_id, true);

        if (!$result) {
            wp_send_json_error('Failed to delete review');
        }

        // Update product rating
        $this->update_product_rating($product_id);

        wp_send_json_success([
            'message' => 'Review deleted successfully!'
        ]);
    }

    public function ajax_get_review() {
        check_ajax_referer('wcrm-nonce', 'security');

        $comment_id = absint($_GET['comment_id'] ?? 0);

        if ($comment_id <= 0) {
            wp_send_json_error('Invalid review ID');
        }

        $comment = get_comment($comment_id);
        if (!$comment) {
            wp_send_json_error('Review not found');
        }

        $rating = get_comment_meta($comment_id, 'rating', true);

        wp_send_json_success([
            'comment_id' => $comment->comment_ID,
            'product_id' => $comment->comment_post_ID,
            'rating' => $rating,
            'review_text' => $comment->comment_content,
            'author' => $comment->comment_author,
            'author_email' => $comment->comment_author_email,
            'date' => $comment->comment_date
        ]);
    }

    public function ajax_list_reviews() {
        check_ajax_referer('wcrm-nonce', 'security');

        $product_id = absint($_GET['product_id'] ?? 0);

        if ($product_id <= 0) {
            wp_send_json_error('Please select a product');
        }

        $args = [
            'post_id' => $product_id,
            'type' => 'review',
            'status' => 'approve',
            'orderby' => 'comment_date',
            'order' => 'DESC'
        ];

        $comments = get_comments($args);
        $reviews = [];

        foreach ($comments as $comment) {
            $rating = get_comment_meta($comment->comment_ID, 'rating', true);
            $reviews[] = [
                'comment_id' => $comment->comment_ID,
                'author' => $comment->comment_author,
                'author_email' => $comment->comment_author_email,
                'rating' => $rating,
                'review_text' => wp_trim_words($comment->comment_content, 20),
                'review_full' => $comment->comment_content,
                'date' => $comment->comment_date
            ];
        }

        wp_send_json_success($reviews);
    }

    private function update_product_rating($product_id) {
        global $wpdb;

        $count = $wpdb->get_var($wpdb->prepare("
            SELECT COUNT(*) FROM $wpdb->comments
            WHERE comment_post_ID = %d
            AND comment_type = 'review'
            AND comment_approved = '1'
        ", $product_id));

        if ($count > 0) {
            $ratings = $wpdb->get_var($wpdb->prepare("
                SELECT SUM(meta_value) FROM $wpdb->commentmeta
                LEFT JOIN $wpdb->comments ON $wpdb->commentmeta.comment_id = $wpdb->comments.comment_ID
                WHERE meta_key = 'rating'
                AND comment_post_ID = %d
                AND comment_approved = '1'
                AND comment_type = 'review'
            ", $product_id));

            $average = number_format($ratings / $count, 2, '.', '');
        } else {
            $average = 0;
        }

        update_post_meta($product_id, '_wc_average_rating', $average);
        update_post_meta($product_id, '_wc_review_count', $count);
    }

    public function main_page() {
        if (!current_user_can('manage_options')) return;
        ?>
        <div class="wrap wcrm-wrap">
            <h1>WooCommerce Review Manager</h1>
            <p>Manually add and edit product reviews with custom users and star ratings.</p>

            <div class="wcrm-container">
                <!-- Add Review Section -->
                <div class="wcrm-card">
                    <h2>Add New Review</h2>
                    <form id="wcrm-add-form">
                        <table class="form-table">
                            <tr>
                                <th>Product <span class="required">*</span></th>
                                <td>
                                    <select id="wcrm-product" name="product_id" style="width: 400px;">
                                        <option value="0">-- Search for product --</option>
                                    </select>
                                    <p class="description">Search by product name or SKU</p>
                                </td>
                            </tr>
                            <tr>
                                <th>Star Rating <span class="required">*</span></th>
                                <td>
                                    <div class="wcrm-star-rating">
                                        <label><input type="radio" name="rating" value="5"> <span class="stars">★★★★★</span> 5 Stars</label>
                                        <label><input type="radio" name="rating" value="4"> <span class="stars">★★★★☆</span> 4 Stars</label>
                                        <label><input type="radio" name="rating" value="3"> <span class="stars">★★★☆☆</span> 3 Stars</label>
                                        <label><input type="radio" name="rating" value="2"> <span class="stars">★★☆☆☆</span> 2 Stars</label>
                                        <label><input type="radio" name="rating" value="1"> <span class="stars">★☆☆☆☆</span> 1 Star</label>
                                    </div>
                                </td>
                            </tr>
                            <tr>
                                <th>User Type <span class="required">*</span></th>
                                <td>
                                    <label style="margin-right: 20px;">
                                        <input type="radio" name="user_type" value="existing" checked> Existing User
                                    </label>
                                    <label>
                                        <input type="radio" name="user_type" value="custom"> Custom Name/Email
                                    </label>
                                </td>
                            </tr>
                            <tr id="existing-user-row">
                                <th>Select User <span class="required">*</span></th>
                                <td>
                                    <select id="wcrm-user" name="user_id" style="width: 400px;">
                                        <option value="0">-- Search for user --</option>
                                    </select>
                                    <p class="description">Search by username, email, or display name</p>
                                </td>
                            </tr>
                            <tr id="custom-name-row" style="display: none;">
                                <th>Custom Name <span class="required">*</span></th>
                                <td>
                                    <input type="text" name="custom_name" id="wcrm-custom-name" class="regular-text" placeholder="John Doe">
                                </td>
                            </tr>
                            <tr id="custom-email-row" style="display: none;">
                                <th>Custom Email <span class="required">*</span></th>
                                <td>
                                    <input type="email" name="custom_email" id="wcrm-custom-email" class="regular-text" placeholder="john@example.com">
                                </td>
                            </tr>
                            <tr>
                                <th>Review Text <span class="required">*</span></th>
                                <td>
                                    <?php
                                    wp_editor('', 'wcrm-review-text', [
                                        'textarea_name' => 'review_text',
                                        'textarea_rows' => 8,
                                        'media_buttons' => false,
                                        'teeny' => true,
                                        'quicktags' => true
                                    ]);
                                    ?>
                                    <p class="description">Enter the review content</p>
                                </td>
                            </tr>
                            <tr>
                                <th>Review Date</th>
                                <td>
                                    <input type="datetime-local" name="review_date" id="wcrm-review-date" class="regular-text">
                                    <p class="description">Leave blank to use current date/time, or set a custom date</p>
                                </td>
                            </tr>
                        </table>
                        <p class="submit">
                            <button type="submit" class="button button-primary button-large">Add Review</button>
                        </p>
                    </form>
                </div>

                <!-- Manage Reviews Section -->
                <div class="wcrm-card">
                    <h2>Manage Existing Reviews</h2>
                    <div class="wcrm-search-section">
                        <label for="wcrm-product-search">Select Product:</label>
                        <select id="wcrm-product-search" style="width: 400px;">
                            <option value="0">-- Search for product --</option>
                        </select>
                        <button type="button" id="wcrm-load-reviews" class="button">Load Reviews</button>
                    </div>

                    <div id="wcrm-reviews-list" style="margin-top: 20px;">
                        <p class="description">Select a product to view its reviews</p>
                    </div>
                </div>

                <!-- Edit Review Modal -->
                <div id="wcrm-edit-modal" class="wcrm-modal" style="display: none;">
                    <div class="wcrm-modal-content">
                        <span class="wcrm-modal-close">&times;</span>
                        <h2>Edit Review</h2>
                        <form id="wcrm-edit-form">
                            <input type="hidden" name="comment_id" id="edit-comment-id">
                            <table class="form-table">
                                <tr>
                                    <th>Reviewer</th>
                                    <td id="edit-reviewer-name" style="padding-top: 10px;"></td>
                                </tr>
                                <tr>
                                    <th>Star Rating <span class="required">*</span></th>
                                    <td>
                                        <div class="wcrm-star-rating">
                                            <label><input type="radio" name="edit_rating" value="5"> <span class="stars">★★★★★</span> 5 Stars</label>
                                            <label><input type="radio" name="edit_rating" value="4"> <span class="stars">★★★★☆</span> 4 Stars</label>
                                            <label><input type="radio" name="edit_rating" value="3"> <span class="stars">★★★☆☆</span> 3 Stars</label>
                                            <label><input type="radio" name="edit_rating" value="2"> <span class="stars">★★☆☆☆</span> 2 Stars</label>
                                            <label><input type="radio" name="edit_rating" value="1"> <span class="stars">★☆☆☆☆</span> 1 Star</label>
                                        </div>
                                    </td>
                                </tr>
                                <tr>
                                    <th>Review Text <span class="required">*</span></th>
                                    <td>
                                        <?php
                                        wp_editor('', 'wcrm-edit-review-text', [
                                            'textarea_name' => 'edit_review_text',
                                            'textarea_rows' => 8,
                                            'media_buttons' => false,
                                            'teeny' => true,
                                            'quicktags' => true
                                        ]);
                                        ?>
                                    </td>
                                </tr>
                                <tr>
                                    <th>Review Date</th>
                                    <td>
                                        <input type="datetime-local" name="edit_review_date" id="wcrm-edit-review-date" class="regular-text">
                                        <p class="description">Change the date/time of this review</p>
                                    </td>
                                </tr>
                            </table>
                            <p class="submit">
                                <button type="submit" class="button button-primary">Update Review</button>
                                <button type="button" class="button wcrm-modal-close">Cancel</button>
                            </p>
                        </form>
                    </div>
                </div>
            </div>
        </div>
        <?php
    }
}

// Initialize
add_action('plugins_loaded', function() {
    if (class_exists('WooCommerce')) {
        WC_Review_Manager::instance();
    }
});
