<?php
/**
 * Plugin Name: WooCommerce Email Exists Message
 * Plugin URI: https://github.com/renthemighty/Plugins
 * Description: Replaces the confusing "The email you entered is incorrect" error with a clearer message when an email is already in use
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
 * Text Domain: wc-email-exists-message
 */

defined('ABSPATH') || exit;

class WC_Email_Exists_Message {

    /**
     * The replacement message
     */
    private $replacement_message = 'That email is already in use, please login or request a password reset';

    /**
     * Messages to replace (various incorrect/confusing messages)
     */
    private $messages_to_replace = [
        'The email you entered is incorrect',
        'The email you entered is incorrect.',
        'An account is already registered with your email address',
        'An account is already registered with your email address.',
        'An account is already registered with your email address. Please log in.',
        'An account is already registered with your email address. <a href="#" class="showlogin">Please log in.</a>',
    ];

    private static $instance = null;

    public static function instance() {
        if (null === self::$instance) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    private function __construct() {
        // Filter translated text
        add_filter('gettext', [$this, 'replace_email_error_message'], 20, 3);

        // Filter WooCommerce registration errors
        add_filter('woocommerce_registration_errors', [$this, 'filter_registration_errors'], 20, 3);

        // Filter WooCommerce process registration errors
        add_filter('woocommerce_process_registration_errors', [$this, 'filter_registration_errors'], 20, 3);

        // Filter Ultimate Member error messages
        add_filter('um_custom_error_message_handler', [$this, 'filter_um_errors'], 20, 2);
        add_filter('um_submit_form_errors_hook', [$this, 'filter_um_form_errors'], 20, 1);

        // General WordPress authentication/registration errors
        add_filter('wp_login_errors', [$this, 'filter_login_errors'], 20, 2);
        add_filter('registration_errors', [$this, 'filter_wp_registration_errors'], 20, 3);
    }

    /**
     * Replace error message in translated text
     */
    public function replace_email_error_message($translated_text, $text, $domain) {
        foreach ($this->messages_to_replace as $message) {
            if (stripos($translated_text, $message) !== false || stripos($text, $message) !== false) {
                return $this->replacement_message;
            }
        }

        // Also check for partial matches
        if (stripos($translated_text, 'email you entered is incorrect') !== false) {
            return $this->replacement_message;
        }

        return $translated_text;
    }

    /**
     * Filter WooCommerce registration errors
     */
    public function filter_registration_errors($errors, $username = '', $email = '') {
        if (is_wp_error($errors)) {
            $error_messages = $errors->get_error_messages();

            foreach ($error_messages as $key => $message) {
                if ($this->should_replace_message($message)) {
                    // Get all error codes
                    $codes = $errors->get_error_codes();

                    // Create new WP_Error with replaced messages
                    $new_errors = new WP_Error();

                    foreach ($codes as $code) {
                        $code_messages = $errors->get_error_messages($code);
                        foreach ($code_messages as $code_message) {
                            if ($this->should_replace_message($code_message)) {
                                $new_errors->add($code, $this->replacement_message);
                            } else {
                                $new_errors->add($code, $code_message);
                            }
                        }
                    }

                    return $new_errors;
                }
            }
        }

        return $errors;
    }

    /**
     * Filter Ultimate Member errors
     */
    public function filter_um_errors($message, $key) {
        if ($this->should_replace_message($message)) {
            return $this->replacement_message;
        }
        return $message;
    }

    /**
     * Filter Ultimate Member form errors
     */
    public function filter_um_form_errors($errors) {
        if (is_array($errors)) {
            foreach ($errors as $key => $error) {
                if (is_string($error) && $this->should_replace_message($error)) {
                    $errors[$key] = $this->replacement_message;
                }
            }
        }
        return $errors;
    }

    /**
     * Filter WordPress login errors
     */
    public function filter_login_errors($errors, $redirect_to = '') {
        if (is_wp_error($errors)) {
            $codes = $errors->get_error_codes();
            $new_errors = new WP_Error();

            foreach ($codes as $code) {
                $messages = $errors->get_error_messages($code);
                foreach ($messages as $message) {
                    if ($this->should_replace_message($message)) {
                        $new_errors->add($code, $this->replacement_message);
                    } else {
                        $new_errors->add($code, $message);
                    }
                }
            }

            return $new_errors;
        }
        return $errors;
    }

    /**
     * Filter WordPress registration errors
     */
    public function filter_wp_registration_errors($errors, $sanitized_user_login, $user_email) {
        return $this->filter_registration_errors($errors, $sanitized_user_login, $user_email);
    }

    /**
     * Check if a message should be replaced
     */
    private function should_replace_message($message) {
        $message_lower = strtolower($message);

        foreach ($this->messages_to_replace as $check) {
            if (stripos($message, $check) !== false) {
                return true;
            }
        }

        // Check for common patterns indicating email already in use
        if (
            stripos($message_lower, 'email you entered is incorrect') !== false ||
            (stripos($message_lower, 'email') !== false && stripos($message_lower, 'already') !== false) ||
            (stripos($message_lower, 'email') !== false && stripos($message_lower, 'registered') !== false)
        ) {
            return true;
        }

        return false;
    }
}

// Initialize
add_action('plugins_loaded', function() {
    WC_Email_Exists_Message::instance();
}, 5); // Priority 5 to load early
