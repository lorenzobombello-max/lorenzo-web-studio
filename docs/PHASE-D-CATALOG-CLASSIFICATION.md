# Phase D catalog classification

Catalog version: `2026-08-12-v1`

This classification controls intake exposure. Every Master Catalog v1 product is
listed exactly once. Customer-selectable does not imply automatic pricing:
manual catalog products remain explicit evidence and trigger review.

## A. Customer-selectable intake

- `dynamic_portfolio`
- `advanced_gallery`
- `live_reviews`
- `booking_widget`
- `advanced_booking`
- `custom_booking`
- `site_search`
- `advanced_search`
- `secure_download`
- `professional_document_flow`
- `customer_portal`
- `extra_simple_products`
- `complex_product`
- `extra_payment_provider`
- `complex_shipping`
- `webshop_accounts`
- `catalog_import`
- `erp_inventory_api`
- `translation`
- `alternative_language_structure`
- `light_copy_optimization`
- `substantial_rewrite`
- `new_copy`
- `specialist_copy`
- `advanced_image_editing`
- `ai_image_set`
- `stock_selection`
- `photography`
- `professional_logo`
- `visual_identity`
- `logo_identity_combo`
- `extended_branding`
- `seo_launch`
- `seo_extra_language`
- `advanced_seo_language`
- `complex_seo`
- `dns_configuration`
- `domain_transfer`
- `simple_hosting_migration`
- `complex_dns_mail_migration`
- `complex_migration`
- `care`
- `care_plus`
- `advanced_newsletter`
- `advanced_analytics`
- `crm_api_erp_automation`

`custom_booking`, `advanced_search`, `customer_portal`, `catalog_import`,
`erp_inventory_api`, `specialist_copy`, `photography`, `extended_branding`,
`advanced_seo_language`, `complex_seo`, both complex migration products and
`crm_api_erp_automation` are customer-recognizable choices with manual review.
Care and Care+ are exposed as optional recurring follow-up services and never
increase the one-time project minimum.

## B. Internal / manual quote

- `custom_page`
- `custom_portal`
- `scope_review`

These are internal fallbacks or scopes that do not provide a useful standalone
customer choice beyond the specific customer-facing manual options above.

## C. Post-sale / recurring service

- `seo_care`
- `seo_growth`
- `adhoc_work`
- `complex_technical_work`
- `five_hour_bundle`

These remain outside the project intake. Care and Care+ are classified in A
because Phase D explicitly exposes them as optional follow-up service evidence.

## D. Already represented

- `starter`
- `professional`
- `extra_standard_page`
- `simple_portfolio`
- `static_gallery`
- `static_reviews`
- `blog_news`
- `basic_quote_form`
- `extended_quote_form`
- `upload_form`
- `complex_form_workflow`
- `webshop_base`
- `primary_language`
- `first_extra_language`
- `second_extra_language`
- `subsequent_extra_language`
- `client_image_integration`
- `rush`

Phase D may improve evidence fidelity for these products, but does not add a
second competing intake choice.

## E. Not needed in intake

- `standard_page`
- `correction_round`
- `responsive_design`
- `technical_foundation`
- `navigation`
- `technical_seo`
- `standard_contact_form`
- `analytics_search_console`
- `content_integration`
- `normal_image_optimization`
- `technical_qa_delivery`
- `social_links`
- `maps_embed`
- `simple_newsletter_embed`
- `extended_information_architecture`
- `professional_component_structure`
- `performance_finish`
- `complex_page`
- `simple_product`
- `standard_payment_provider`
- `standard_shipping`
- `normal_categories`
- `project_domain_configuration`
- `existing_domain_link`
- `standard_hosting_setup`
- `extra_revision`

These are package internals, bundle allowances, implementation details or
post-delivery operations rather than useful independent customer choices.

## Homepage dependency

`assets/js/homepage-studio.js` owns an inactive legacy indication widget with
hardcoded ranges EUR 1,800-3,200, EUR 3,200-5,800 and from EUR 5,800. The current
homepage does not provide the matching `pricingRange` widget DOM, but accidental
reactivation would conflict with Master Catalog v1. Migrate or remove this asset
in a dedicated homepage pricing-coherence phase; Phase D does not change it.