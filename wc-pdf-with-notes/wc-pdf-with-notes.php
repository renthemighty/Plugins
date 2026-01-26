<?php
/**
 * Plugin Name: WooCommerce PDF Documents with Notes
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Generate PDF invoices and packing slips with proper note filtering (private notes on packing slip, customer notes on invoice)
 * Version: 1.0.0
 * Author: Megatron
 * Author URI: https://github.com/renthemighty
 * Requires at least: 5.0
 * Tested up to: 6.4
 * Requires PHP: 7.2
 * WC requires at least: 5.0
 * WC tested up to: 8.5
 * License: GPL v2 or later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 */

defined('ABSPATH') || exit;

class WC_PDF_With_Notes {

    private static $instance = null;

    public static function instance() {
        if (null === self::$instance) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        // Add action buttons to orders page
        add_filter('woocommerce_admin_order_actions', [$this, 'add_order_actions'], 100, 2);

        // Handle PDF generation requests
        add_action('admin_init', [$this, 'handle_pdf_generation']);

        // Hook into existing PDF plugin to add notes
        add_action('wpo_wcpdf_after_order_details', [$this, 'add_notes_to_document'], 10, 2);
    }

    /**
     * Add PDF action buttons to orders page
     */
    public function add_order_actions($actions, $order) {
        $order_id = is_callable([$order, 'get_id']) ? $order->get_id() : $order->id;

        // Add Packing Slip button
        $actions['pdf_packing_slip'] = [
            'url'    => wp_nonce_url(admin_url('admin.php?action=generate_pdf_packing_slip&order_id=' . $order_id), 'generate_pdf_packing_slip'),
            'name'   => __('Packing Slip', 'wc-pdf-with-notes'),
            'action' => 'view_packing_slip',
        ];

        // Add Invoice button
        $actions['pdf_invoice'] = [
            'url'    => wp_nonce_url(admin_url('admin.php?action=generate_pdf_invoice&order_id=' . $order_id), 'generate_pdf_invoice'),
            'name'   => __('Invoice', 'wc-pdf-with-notes'),
            'action' => 'view_invoice',
        ];

        return $actions;
    }

    /**
     * Handle PDF generation requests
     */
    public function handle_pdf_generation() {
        if (!isset($_GET['action']) || !isset($_GET['order_id'])) {
            return;
        }

        $action = $_GET['action'];
        $order_id = intval($_GET['order_id']);

        if ($action === 'generate_pdf_packing_slip') {
            check_admin_referer('generate_pdf_packing_slip');
            $this->generate_packing_slip_pdf($order_id);
        } elseif ($action === 'generate_pdf_invoice') {
            check_admin_referer('generate_pdf_invoice');
            $this->generate_invoice_pdf($order_id);
        }
    }

    /**
     * Generate packing slip PDF
     */
    private function generate_packing_slip_pdf($order_id) {
        // Check if PDF Invoices & Packing Slips plugin is active
        if (function_exists('wcpdf_get_document')) {
            // Use existing plugin to generate packing slip
            $document = wcpdf_get_document('packing-slip', $order_id);
            if ($document) {
                $document->output_pdf();
                exit;
            }
        }

        // Fallback: generate simple PDF
        $this->generate_simple_pdf($order_id, 'packing-slip');
    }

    /**
     * Generate invoice PDF
     */
    private function generate_invoice_pdf($order_id) {
        // Check if PDF Invoices & Packing Slips plugin is active
        if (function_exists('wcpdf_get_document')) {
            // Use existing plugin to generate invoice
            $document = wcpdf_get_document('invoice', $order_id);
            if ($document) {
                $document->output_pdf();
                exit;
            }
        }

        // Fallback: generate simple PDF
        $this->generate_simple_pdf($order_id, 'invoice');
    }

    /**
     * Add notes to PDF document based on type
     */
    public function add_notes_to_document($type, $order) {
        $order_id = is_callable([$order, 'get_id']) ? $order->get_id() : $order->id;

        if ($type === 'packing-slip') {
            // Show PRIVATE notes on packing slip
            $notes = $this->get_private_notes($order_id);
            $this->display_notes($notes, 'Private Notes');
        } elseif ($type === 'invoice') {
            // Show CUSTOMER notes on invoice
            $notes = $this->get_customer_notes($order_id);
            $this->display_notes($notes, 'Customer Notes');
        }
    }

    /**
     * Get private notes (manually entered by staff, NOT customer-facing)
     */
    private function get_private_notes($order_id) {
        global $wpdb;

        // Private notes:
        // - user_id > 0 (manually entered by staff)
        // - is_customer_note != 1 (NOT customer-facing)
        $query = $wpdb->prepare("
            SELECT c.comment_ID, c.comment_content, c.comment_date, c.user_id
            FROM {$wpdb->comments} c
            LEFT JOIN {$wpdb->commentmeta} cm ON c.comment_ID = cm.comment_id AND cm.meta_key = 'is_customer_note'
            WHERE c.comment_post_ID = %d
            AND c.comment_type = 'order_note'
            AND c.comment_approved = '1'
            AND c.user_id > 0
            AND (cm.meta_value IS NULL OR cm.meta_value = '0' OR cm.meta_value = '')
            ORDER BY c.comment_date_gmt DESC
        ", $order_id);

        return $wpdb->get_results($query);
    }

    /**
     * Get customer notes (customer-facing notes)
     */
    private function get_customer_notes($order_id) {
        global $wpdb;

        // Customer notes:
        // - is_customer_note = 1 (customer-facing)
        $query = $wpdb->prepare("
            SELECT c.comment_ID, c.comment_content, c.comment_date, c.user_id
            FROM {$wpdb->comments} c
            INNER JOIN {$wpdb->commentmeta} cm ON c.comment_ID = cm.comment_id
            WHERE c.comment_post_ID = %d
            AND c.comment_type = 'order_note'
            AND c.comment_approved = '1'
            AND cm.meta_key = 'is_customer_note'
            AND cm.meta_value = '1'
            ORDER BY c.comment_date_gmt DESC
        ", $order_id);

        return $wpdb->get_results($query);
    }

    /**
     * Display notes in PDF
     */
    private function display_notes($notes, $heading) {
        if (empty($notes)) {
            return;
        }
        ?>
        <div class="wc-pdf-notes" style="margin-top: 20px; padding: 15px; border: 1px solid #ddd; background: #f9f9f9;">
            <h3 style="margin: 0 0 10px 0; font-size: 14px; border-bottom: 2px solid #333; padding-bottom: 5px;">
                <?php echo esc_html($heading); ?>
            </h3>
            <?php foreach ($notes as $note): ?>
                <div style="margin-bottom: 10px; padding-bottom: 10px; border-bottom: 1px solid #ddd;">
                    <div style="font-size: 10px; color: #666; margin-bottom: 5px;">
                        <?php echo date_i18n(get_option('date_format') . ' ' . get_option('time_format'), strtotime($note->comment_date)); ?>
                    </div>
                    <div style="font-size: 11px;">
                        <?php echo wp_kses_post(wpautop($note->comment_content)); ?>
                    </div>
                </div>
            <?php endforeach; ?>
        </div>
        <?php
    }

    /**
     * Generate simple PDF (fallback if main plugin not active)
     */
    private function generate_simple_pdf($order_id, $type) {
        $order = wc_get_order($order_id);
        if (!$order) {
            wp_die('Order not found');
        }

        // Simple HTML output that can be printed to PDF
        header('Content-Type: text/html; charset=utf-8');
        ?>
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title><?php echo ucfirst($type); ?> #<?php echo $order->get_order_number(); ?></title>
            <style>
                body { font-family: Arial, sans-serif; font-size: 12px; }
                h1 { font-size: 24px; margin-bottom: 20px; }
                .order-details { margin: 20px 0; }
                .order-details th { text-align: left; padding: 5px; }
                .order-details td { padding: 5px; }
                table { width: 100%; border-collapse: collapse; }
                table th, table td { border: 1px solid #ddd; padding: 8px; }
            </style>
        </head>
        <body>
            <h1><?php echo ucfirst($type); ?> #<?php echo $order->get_order_number(); ?></h1>

            <div class="order-details">
                <p><strong>Date:</strong> <?php echo $order->get_date_created()->date_i18n(get_option('date_format')); ?></p>
                <p><strong>Customer:</strong> <?php echo $order->get_formatted_billing_full_name(); ?></p>
            </div>

            <table>
                <thead>
                    <tr>
                        <th>Product</th>
                        <th>Quantity</th>
                        <th>Price</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($order->get_items() as $item): ?>
                    <tr>
                        <td><?php echo $item->get_name(); ?></td>
                        <td><?php echo $item->get_quantity(); ?></td>
                        <td><?php echo wc_price($item->get_total()); ?></td>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>

            <?php
            // Add notes
            if ($type === 'packing-slip') {
                $notes = $this->get_private_notes($order_id);
                $this->display_notes($notes, 'Private Notes');
            } else {
                $notes = $this->get_customer_notes($order_id);
                $this->display_notes($notes, 'Customer Notes');
            }
            ?>

            <script>
                // Auto-print and close
                window.onload = function() {
                    window.print();
                };
            </script>
        </body>
        </html>
        <?php
        exit;
    }
}

// Initialize
add_action('plugins_loaded', function() {
    if (class_exists('WooCommerce')) {
        WC_PDF_With_Notes::instance();
    }
});
