<?php
/*
 * Plugin Name: Custom WP-Admin Theme
 * Author: MetWrk SafeHouse
 * Author URI: https://metwrk.com
 * Version: 1.1
 * Description: "Super lightweight wp-admin theme for wordpress.
*/

function my_admin_theme_style() {
    wp_enqueue_style('my-admin-theme', plugins_url('wp-admin.css', __FILE__));
}
add_action('admin_enqueue_scripts', 'my_admin_theme_style');
add_action('login_enqueue_scripts', 'my_admin_theme_style');

?>