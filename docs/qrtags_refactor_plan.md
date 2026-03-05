# QRTags Refactor Plan (File-by-File)

## Scope
- Codebase: `lib/`
- Goal: reduce risk/regressions by splitting very large UI files into smaller widgets + controllers/services.
- Constraint: no behavior changes during extraction passes.

## Priority Order
1. `lib/pages/total_page.dart`
2. `lib/pages/generate_page.dart`
3. `lib/pages/scan_page.dart`
4. `lib/pages/inventory_page.dart`
5. `lib/main.dart`
6. `lib/pages/old_page.dart`
7. `lib/widgets/settings_button.dart`
8. Remaining medium/small files

## File-by-File Plan
| Current File | Lines | Plan | Exact Split Targets |
|---|---:|---|---|
| `lib/main.dart` | 1072 | Split app shell/bootstrap/auth gates and top app bar actions | `lib/app/app_root.dart`, `lib/app/app_theme.dart`, `lib/app/bootstrap_gate.dart`, `lib/app/auth_gate.dart`, `lib/app/version_gate.dart`, `lib/app/home_shell.dart`, `lib/app/widgets/gst_settings_button.dart`, `lib/app/widgets/vibrating_title_settings_button.dart` |
| `lib/data/tag_migration_runner.dart` | 75 | Keep (small, single responsibility) | No split |
| `lib/data/tag_repository.dart` | 137 | Keep, optional Firestore adapter later | Optional: `lib/data/tag_repository_firestore.dart` |
| `lib/features/generate/generate_tag_normalizer.dart` | 77 | Keep | No split |
| `lib/features/inventory/inventory_tag_sorter.dart` | 44 | Keep | No split |
| `lib/features/scan/scan_selection_store.dart` | 41 | Keep | No split |
| `lib/features/selection/selected_items_state.dart` | 58 | Keep | No split |
| `lib/features/total/payment_entry_calculator.dart` | 36 | Keep | No split |
| `lib/features/total/total_customer_validator.dart` | 13 | Keep | No split |
| `lib/models/edit_tag_request.dart` | 8 | Keep | No split |
| `lib/models/tag_record.dart` | 143 | Keep model; move parsing helpers only if reused by many pages | Optional: `lib/models/tag_record_parser.dart` |
| `lib/pages/generate_page.dart` | 2956 | Split into feature folder with controller + sections + dialogs | `lib/pages/generate/generate_page.dart`, `lib/pages/generate/generate_controller.dart`, `lib/pages/generate/generate_draft_store.dart`, `lib/pages/generate/master_data_store.dart`, `lib/pages/generate/widgets/master_data_bar.dart`, `lib/pages/generate/widgets/base_fields_section.dart`, `lib/pages/generate/widgets/less_entries_section.dart`, `lib/pages/generate/widgets/additional_entries_section.dart`, `lib/pages/generate/widgets/generate_actions_section.dart`, `lib/pages/generate/widgets/category_admin_dialog.dart`, `lib/pages/generate/widgets/item_admin_dialog.dart` |
| `lib/pages/inventory_page.dart` | 1477 | Split list rendering, filters/actions, and export/transfer workflows | `lib/pages/inventory/inventory_page.dart`, `lib/pages/inventory/inventory_controller.dart`, `lib/pages/inventory/widgets/inventory_filters_bar.dart`, `lib/pages/inventory/widgets/inventory_tile.dart`, `lib/pages/inventory/widgets/inventory_list_section.dart`, `lib/pages/inventory/widgets/newly_created_section.dart`, `lib/pages/inventory/export/inventory_pdf_exporter.dart`, `lib/pages/inventory/services/inventory_transfer_service.dart` |
| `lib/pages/login_page.dart` | 198 | Keep mostly; optional form extraction | Optional: `lib/pages/login/widgets/login_form.dart` |
| `lib/pages/old_page.dart` | 906 | Split form state/calculation and entries list | `lib/pages/old/old_page.dart`, `lib/pages/old/old_controller.dart`, `lib/pages/old/widgets/old_form_section.dart`, `lib/pages/old/widgets/old_items_list.dart`, `lib/pages/old/widgets/old_totals_bar.dart` |
| `lib/pages/sales_page.dart` | 225 | Keep page; extract mapper if reused | Optional: `lib/pages/sales/sales_mapper.dart` |
| `lib/pages/scan_page.dart` | 2311 | Split scan actions, grouped list, manual dialog orchestration, and styles | `lib/pages/scan/scan_page.dart`, `lib/pages/scan/scan_controller.dart`, `lib/pages/scan/widgets/scan_quick_actions_card.dart`, `lib/pages/scan/widgets/scan_action_buttons.dart`, `lib/pages/scan/widgets/scan_grouped_list.dart`, `lib/pages/scan/widgets/scan_group_section.dart`, `lib/pages/scan/widgets/scan_item_card.dart`, `lib/pages/scan/widgets/scan_bottom_summary_bar.dart`, `lib/pages/scan/widgets/live_qr_scanner_page.dart`, `lib/pages/scan/widgets/scanner_overlay.dart`, `lib/pages/scan/manual/manual_item_dialog.dart`, `lib/pages/scan/manual/manual_item_mapper.dart` |
| `lib/pages/selected_page.dart` | 392 | Split persistence + row widget | `lib/pages/selected/selected_page.dart`, `lib/pages/selected/selected_controller.dart`, `lib/pages/selected/widgets/selected_item_card.dart`, `lib/pages/selected/widgets/selected_totals_bar.dart` |
| `lib/pages/total_page.dart` | 3639 | Largest risk file: split TTS, payment entries, takeaway optimizer, and PDF bill builder | `lib/pages/total/total_page.dart`, `lib/pages/total/total_controller.dart`, `lib/pages/total/tts/due_amount_tts.dart`, `lib/pages/total/payments/payment_entries_section.dart`, `lib/pages/total/payments/payment_entry_row.dart`, `lib/pages/total/payments/payment_draft_store.dart`, `lib/pages/total/takeaway/takeaway_optimizer.dart`, `lib/pages/total/takeaway/takeaway_widgets.dart`, `lib/pages/total/pdf/total_bill_pdf_builder.dart`, `lib/pages/total/pdf/total_bill_models.dart`, `lib/pages/total/pdf/total_bill_theme.dart`, `lib/pages/total/widgets/selected_items_sections.dart`, `lib/pages/total/widgets/old_items_section.dart` |
| `lib/utils/price_calculator.dart` | 145 | Keep, but add interfaces if future rate providers vary | Optional: `lib/utils/rate_provider.dart` |
| `lib/utils/qr_crypto.dart` | 42 | Keep | No split |
| `lib/utils/qr_logo_loader.dart` | 87 | Keep | No split |
| `lib/utils/sales_notifier.dart` | 9 | Keep | No split |
| `lib/utils/selection_notifier.dart` | 9 | Keep | No split |
| `lib/utils/share_file_namer.dart` | 62 | Keep | No split |
| `lib/widgets/manual_item_dialog_body.dart` | 62 | Keep | No split |
| `lib/widgets/settings_button.dart` | 449 | Split rates sync, dialog, and input formatter | `lib/widgets/settings/settings_button.dart`, `lib/widgets/settings/rate_settings_dialog.dart`, `lib/widgets/settings/rates_sync_service.dart`, `lib/widgets/settings/indian_rate_input_formatter.dart`, `lib/widgets/settings/return_rate_text.dart` |
| `lib/widgets/shared_item_form_layout.dart` | 117 | Keep | No split |

## Exact Extraction Sequence (Safe)
1. Move pure helper methods/classes first (no UI behavior): formatters, parsers, DTOs, constants.
2. Extract stateless widgets next (row/cards/sections) and keep callbacks from parent.
3. Extract services/stores (`SharedPreferences`, Firestore wrappers) behind small APIs.
4. Extract controller/state classes last, keep page integration with same public behavior.
5. After each extraction:
   - run `flutter analyze`
   - run `flutter test`
   - manual smoke test: Generate, Scan, Total bill preview/print/share

## Definition of Done per File
- Original file shrunk and focused on composition.
- No visual/behavior change.
- Analyzer and tests green.
- New unit tests for extracted pure logic (formatter/calculator/parser/optimizer).

## Notes
- `lib/pages/bkp.txt` has been removed from source tree.
