<?php
/**
 * Plugin Name: Petra listing prices
 * Description: Prints each listing's price in the currency Tokko sent for it.
 * Version: 1.0.0
 *
 * WooCommerce renders one currency symbol for the whole store, so a peso
 * listing reads as dollars. The sync already writes the real currency into
 * the Precio attribute ("USD 88000", "ARS 950000"), so read it from there
 * rather than storing the currency a second time.
 */

defined('ABSPATH') || exit;

const PETRA_PRICE_LABELS = array(
    'USD' => 'USD',
    'ARS' => '$',
);

add_filter('woocommerce_get_price_html', 'petra_listing_price_html', 20, 2);

function petra_listing_price_html($html, $product)
{
    $currency = petra_listing_currency($product);
    $amount   = $product->get_price();

    if (null === $currency || '' === $amount || null === $amount) {
        return $html;
    }

    return '<span class="woocommerce-Price-amount amount">'
        . esc_html(PETRA_PRICE_LABELS[$currency] . ' ' . number_format((float) $amount, 0, ',', '.'))
        . '</span>';
}

function petra_listing_currency($product)
{
    $id = $product->is_type('variation') ? $product->get_parent_id() : $product->get_id();

    $terms = wc_get_product_terms($id, 'pa_precio', array('fields' => 'names'));
    if (empty($terms)) {
        return null;
    }

    $code = strtoupper(strtok(trim($terms[0]), ' '));

    return isset(PETRA_PRICE_LABELS[$code]) ? $code : null;
}
