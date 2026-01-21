<?php
/**
 * Bundle Product Class
 *
 * @package WC_Simple_Bundle
 */

defined('ABSPATH') || exit;

/**
 * Bundle Product Class
 * 
 * The key to making product types work in WooCommerce:
 * 1. Extend WC_Product
 * 2. Set product_type in constructor
 * 3. Return correct type in get_type()
 * 4. WooCommerce handles the rest automatically
 */
class WC_Product_Bundle extends WC_Product {
    
    /**
     * Initialize bundle product
     */
    public function __construct($product = 0) {
        $this->product_type = 'bundle';
        parent::__construct($product);
    }
    
    /**
     * Get internal type - CRITICAL for WooCommerce to recognize this product type
     */
    public function get_type() {
        return 'bundle';
    }
    
    /**
     * Get bundle data
     */
    public function get_bundle_data() {
        return get_post_meta($this->get_id(), '_bundle_data', true);
    }
    
    /**
     * Set bundle data
     */
    public function set_bundle_data($bundle_data) {
        update_post_meta($this->get_id(), '_bundle_data', $bundle_data);
    }
    
    /**
     * Bundle products are purchasable if they have a price
     */
    public function is_purchasable() {
        $purchasable = true;
        
        if ($this->get_price() === '') {
            $purchasable = false;
        }
        
        if ('publish' !== $this->get_status() && !current_user_can('edit_post', $this->get_id())) {
            $purchasable = false;
        }
        
        return apply_filters('woocommerce_is_purchasable', $purchasable, $this);
    }
    
    /**
     * Bundles are always in stock if not managing stock
     */
    public function is_in_stock() {
        if ($this->managing_stock()) {
            return parent::is_in_stock();
        }
        return true;
    }
}
