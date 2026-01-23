<?php
/**
 * Plugin Name: WooCommerce Packing Slip Private Notes
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Adds ONLY private (internal) order notes to WooCommerce packing slips
 * Version: 2.0.2
 * Author: Megatron
 * Author URI: https://github.com/renthemighty
 * Requires at least: 5.0
 * Tested up to: 6.4
 * Requires PHP: 7.2
 * WC requires at least: 5.0
 * WC tested up to: 8.5
 * License: GPL v2 or later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: wc-packing-slip-notes
 */

defined('ABSPATH') || exit;

class WC_Packing_Slip_Notes {

    private static $instance = null;

    public static function instance() {
        if (null === self::$instance) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        // Hook into WooCommerce PDF Invoices & Packing Slips plugin
        add_action('wpo_wcpdf_after_order_details', [$this, 'add_notes_to_packing_slip'], 10, 2);

        // Hook into other popular packing slip plugins
        add_action('wc_pip_after_body', [$this, 'add_notes_to_pip'], 10, 3);

        // Generic hook that can work with custom packing slips
        add_action('woocommerce_admin_order_data_after_order_details', [$this, 'add_notes_section_admin']);

        // Add settings to WooCommerce
        add_filter('woocommerce_get_settings_advanced', [$this, 'add_settings'], 10, 2);
        add_filter('woocommerce_get_sections_advanced', [$this, 'add_section']);

        // Add custom CSS for packing slips
        add_action('wpo_wcpdf_custom_styles', [$this, 'add_custom_styles']);
    }

    /**
     * Add "Packing Slip Notes" section to Advanced settings
     */
    public function add_section($sections) {
        $sections['packing-slip-notes'] = __('Packing Slip Notes', 'wc-packing-slip-notes');
        return $sections;
    }

    /**
     * Add settings to the Packing Slip Notes section
     */
    public function add_settings($settings, $current_section) {
        if ('packing-slip-notes' !== $current_section) {
            return $settings;
        }

        $custom_settings = [
            [
                'title' => __('Packing Slip Notes Settings', 'wc-packing-slip-notes'),
                'type'  => 'title',
                'desc'  => __('Configure how private notes appear on packing slips. Only private/internal notes (not customer notes) will be displayed.', 'wc-packing-slip-notes'),
                'id'    => 'wc_packing_slip_notes_settings'
            ],
            [
                'title'    => __('Enable Private Notes', 'wc-packing-slip-notes'),
                'desc'     => __('Display private order notes on packing slips', 'wc-packing-slip-notes'),
                'id'       => 'wc_packing_slip_notes_enabled',
                'default'  => 'yes',
                'type'     => 'checkbox',
            ],
            [
                'title'    => __('Notes Heading', 'wc-packing-slip-notes'),
                'desc'     => __('The heading text displayed above the notes section.', 'wc-packing-slip-notes'),
                'id'       => 'wc_packing_slip_notes_heading',
                'default'  => 'Internal Notes',
                'type'     => 'text',
            ],
            [
                'title'    => __('Include Timestamps', 'wc-packing-slip-notes'),
                'desc'     => __('Show when each note was added', 'wc-packing-slip-notes'),
                'id'       => 'wc_packing_slip_notes_timestamps',
                'default'  => 'yes',
                'type'     => 'checkbox',
            ],
            [
                'title'    => __('Include Author', 'wc-packing-slip-notes'),
                'desc'     => __('Show who added each note', 'wc-packing-slip-notes'),
                'id'       => 'wc_packing_slip_notes_author',
                'default'  => 'no',
                'type'     => 'checkbox',
            ],
            [
                'title'    => __('Maximum Notes', 'wc-packing-slip-notes'),
                'desc'     => __('Maximum number of notes to display (0 = unlimited).', 'wc-packing-slip-notes'),
                'id'       => 'wc_packing_slip_notes_limit',
                'default'  => '0',
                'type'     => 'number',
                'custom_attributes' => [
                    'step' => '1',
                    'min'  => '0'
                ]
            ],
            [
                'type' => 'sectionend',
                'id'   => 'wc_packing_slip_notes_settings'
            ]
        ];

        return $custom_settings;
    }

    /**
     * Get private notes for an order
     * Only returns private/internal notes, excludes customer-facing notes
     */
    private function get_private_notes($order_id) {
        // Use wc_get_order_notes() function with type='internal' to get ONLY private notes
        if (!function_exists('wc_get_order_notes')) {
            return [];
        }

        // Get ONLY internal/private notes by specifying type parameter
        // type='internal' returns only private notes (not customer-facing)
        $notes = wc_get_order_notes([
            'order_id' => $order_id,
            'type'     => 'internal', // THIS is the key - gets ONLY private notes
        ]);

        if (empty($notes)) {
            return [];
        }

        // Convert to format expected by format_notes()
        $private_notes = [];
        foreach ($notes as $note) {
            $private_notes[] = (object)[
                'comment_ID' => isset($note->id) ? $note->id : 0,
                'comment_content' => isset($note->content) ? $note->content : '',
                'comment_date' => isset($note->date_created) && is_object($note->date_created) ? $note->date_created->date('Y-m-d H:i:s') : '',
                'user_id' => isset($note->added_by_user) ? 1 : 0,
            ];
        }

        return $private_notes;
    }

    /**
     * Format notes for display
     */
    private function format_notes($notes, $order_id = 0) {
        if (empty($notes)) {
            return '';
        }

        $enabled = get_option('wc_packing_slip_notes_enabled', 'yes');
        if ('yes' !== $enabled) {
            return '';
        }

        $heading = get_option('wc_packing_slip_notes_heading', 'Internal Notes');
        $show_timestamps = get_option('wc_packing_slip_notes_timestamps', 'yes') === 'yes';
        $show_author = get_option('wc_packing_slip_notes_author', 'no') === 'yes';
        $limit = intval(get_option('wc_packing_slip_notes_limit', 0));

        // Limit notes if configured
        if ($limit > 0 && count($notes) > $limit) {
            $notes = array_slice($notes, 0, $limit);
        }

        $output = '<div class="wc-packing-slip-notes">';
        $output .= '<h3>' . esc_html($heading) . '</h3>';
        $output .= '<div class="notes-list">';

        foreach ($notes as $note) {
            $output .= '<div class="note-item">';

            if ($show_timestamps || $show_author) {
                $output .= '<div class="note-meta">';

                if ($show_timestamps) {
                    $date = date_i18n(get_option('date_format') . ' ' . get_option('time_format'), strtotime($note->comment_date));
                    $output .= '<span class="note-date">' . esc_html($date) . '</span>';
                }

                if ($show_author) {
                    $user = get_user_by('id', $note->user_id);
                    $author = $user ? $user->display_name : __('System', 'wc-packing-slip-notes');
                    if ($show_timestamps) {
                        $output .= ' <span class="note-separator">|</span> ';
                    }
                    $output .= '<span class="note-author">' . esc_html($author) . '</span>';
                }

                $output .= '</div>';
            }

            $output .= '<div class="note-content">' . wp_kses_post(wpautop($note->comment_content)) . '</div>';
            $output .= '</div>';
        }

        $output .= '</div>';
        $output .= '</div>';

        return $output;
    }

    /**
     * Add notes to WooCommerce PDF Invoices & Packing Slips plugin
     * Hook: wpo_wcpdf_after_order_details
     */
    public function add_notes_to_packing_slip($type, $order) {
        // Only add to packing slips, not invoices
        if ($type !== 'packing-slip') {
            return;
        }

        $order_id = is_callable([$order, 'get_id']) ? $order->get_id() : $order->id;
        $notes = $this->get_private_notes($order_id);

        echo $this->format_notes($notes, $order_id);
    }

    /**
     * Add notes to WooCommerce Print Invoices/Packing Lists plugin
     * Hook: wc_pip_after_body
     */
    public function add_notes_to_pip($type, $action, $document) {
        // Only add to packing lists
        if ($type !== 'packing-list') {
            return;
        }

        $order = $document->order;
        $order_id = is_callable([$order, 'get_id']) ? $order->get_id() : $order->id;
        $notes = $this->get_private_notes($order_id);

        echo $this->format_notes($notes, $order_id);
    }

    /**
     * Add notes section in admin order details
     * This helps admins preview what will appear on the packing slip
     */
    public function add_notes_section_admin($order) {
        $enabled = get_option('wc_packing_slip_notes_enabled', 'yes');
        if ('yes' !== $enabled) {
            return;
        }

        $order_id = is_callable([$order, 'get_id']) ? $order->get_id() : $order->id;
        $notes = $this->get_private_notes($order_id);

        if (empty($notes)) {
            return;
        }

        echo '<div class="order_data_column" style="width: 100%; margin-top: 20px;">';
        echo '<h3>' . __('Notes on Packing Slip', 'wc-packing-slip-notes') . ' <span class="tips" data-tip="' . __('These private notes will appear on the packing slip', 'wc-packing-slip-notes') . '">?</span></h3>';
        echo '<div style="padding: 10px; background: #f9f9f9; border: 1px solid #ddd;">';
        echo $this->format_notes($notes, $order_id);
        echo '</div>';
        echo '</div>';
    }

    /**
     * Add custom CSS for packing slips
     */
    public function add_custom_styles($document_type) {
        if ($document_type !== 'packing-slip') {
            return;
        }
        ?>
        <style>
            .wc-packing-slip-notes {
                margin-top: 20px;
                padding: 15px;
                border: 1px solid #ddd;
                background-color: #f9f9f9;
                page-break-inside: avoid;
            }
            .wc-packing-slip-notes h3 {
                margin: 0 0 15px 0;
                font-size: 14px;
                font-weight: bold;
                text-transform: uppercase;
                border-bottom: 2px solid #333;
                padding-bottom: 5px;
            }
            .wc-packing-slip-notes .notes-list {
                margin: 0;
            }
            .wc-packing-slip-notes .note-item {
                margin-bottom: 12px;
                padding-bottom: 12px;
                border-bottom: 1px solid #ddd;
            }
            .wc-packing-slip-notes .note-item:last-child {
                margin-bottom: 0;
                padding-bottom: 0;
                border-bottom: none;
            }
            .wc-packing-slip-notes .note-meta {
                font-size: 10px;
                color: #666;
                margin-bottom: 5px;
                font-style: italic;
            }
            .wc-packing-slip-notes .note-content {
                font-size: 11px;
                line-height: 1.4;
                color: #333;
            }
            .wc-packing-slip-notes .note-content p {
                margin: 0 0 5px 0;
            }
            .wc-packing-slip-notes .note-content p:last-child {
                margin-bottom: 0;
            }
            .wc-packing-slip-notes .note-separator {
                margin: 0 5px;
            }
        </style>
        <?php
    }
}

// Initialize
add_action('plugins_loaded', function() {
    if (class_exists('WooCommerce')) {
        WC_Packing_Slip_Notes::instance();
    }
});
