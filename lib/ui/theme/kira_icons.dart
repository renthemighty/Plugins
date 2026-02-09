// Kira - The Receipt Saver
// Semantic icon mappings for the icon-forward UI.
//
// This file centralises every icon reference so that swapping to a custom icon
// font (e.g. the bundled KiraIcons.ttf) later requires changes only here.

import 'package:flutter/material.dart';

/// Semantic icon constants used throughout the Kira UI.
///
/// All icons currently map to Material Icons. When the custom KiraIcons font
/// is ready, update the mappings here and the rest of the app follows.
class KiraIcons {
  KiraIcons._();

  // ---- Navigation ----
  static const IconData home = Icons.home_rounded;
  static const IconData reports = Icons.bar_chart_rounded;
  static const IconData alerts = Icons.notifications_rounded;
  static const IconData settings = Icons.settings_rounded;

  // ---- Core actions ----
  static const IconData camera = Icons.camera_alt_rounded;
  static const IconData capture = Icons.add_a_photo_rounded;
  static const IconData receipt = Icons.receipt_long_rounded;
  static const IconData save = Icons.check_circle_rounded;
  static const IconData delete = Icons.delete_outline_rounded;
  static const IconData edit = Icons.edit_rounded;
  static const IconData approve = Icons.thumb_up_alt_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData filter = Icons.filter_list_rounded;
  static const IconData sort = Icons.sort_rounded;
  static const IconData share = Icons.share_rounded;

  // ---- Sync & cloud ----
  static const IconData sync = Icons.sync_rounded;
  static const IconData syncDone = Icons.cloud_done_rounded;
  static const IconData syncPending = Icons.cloud_upload_rounded;
  static const IconData syncFailed = Icons.cloud_off_rounded;
  static const IconData syncOffline = Icons.wifi_off_rounded;
  static const IconData cloud = Icons.cloud_rounded;

  // ---- Storage ----
  static const IconData folder = Icons.folder_rounded;
  static const IconData folderOpen = Icons.folder_open_rounded;
  static const IconData storage = Icons.sd_storage_rounded;
  static const IconData googleDrive = Icons.add_to_drive_rounded;
  static const IconData cloudStorage = Icons.cloud_circle_rounded;

  // ---- Date & time ----
  static const IconData calendar = Icons.calendar_today_rounded;
  static const IconData dateRange = Icons.date_range_rounded;
  static const IconData clock = Icons.access_time_rounded;

  // ---- Categories ----
  static const IconData category = Icons.category_rounded;
  static const IconData meals = Icons.restaurant_rounded;
  static const IconData travel = Icons.flight_rounded;
  static const IconData office = Icons.business_center_rounded;
  static const IconData supplies = Icons.inventory_2_rounded;
  static const IconData fuel = Icons.local_gas_station_rounded;
  static const IconData lodging = Icons.hotel_rounded;
  static const IconData other = Icons.more_horiz_rounded;

  // ---- Reports & export ----
  static const IconData exportIcon = Icons.file_download_rounded;
  static const IconData csv = Icons.table_chart_rounded;
  static const IconData pdf = Icons.picture_as_pdf_rounded;
  static const IconData chart = Icons.pie_chart_rounded;
  static const IconData summary = Icons.summarize_rounded;

  // ---- Security & access ----
  static const IconData lock = Icons.lock_rounded;
  static const IconData unlock = Icons.lock_open_rounded;
  static const IconData fingerprint = Icons.fingerprint_rounded;
  static const IconData shield = Icons.shield_rounded;
  static const IconData key = Icons.vpn_key_rounded;

  // ---- Workspace & business ----
  static const IconData workspace = Icons.workspaces_rounded;
  static const IconData trip = Icons.luggage_rounded;
  static const IconData team = Icons.group_rounded;
  static const IconData person = Icons.person_rounded;
  static const IconData admin = Icons.admin_panel_settings_rounded;
  static const IconData business = Icons.business_rounded;

  // ---- Integrations ----
  static const IconData integrations = Icons.extension_rounded;
  static const IconData link = Icons.link_rounded;
  static const IconData unlink = Icons.link_off_rounded;

  // ---- Status & alerts ----
  static const IconData warning = Icons.warning_amber_rounded;
  static const IconData error = Icons.error_outline_rounded;
  static const IconData info = Icons.info_outline_rounded;
  static const IconData success = Icons.check_circle_outline_rounded;
  static const IconData integrity = Icons.verified_user_rounded;
  static const IconData quarantine = Icons.gpp_maybe_rounded;

  // ---- OCR ----
  static const IconData ocr = Icons.document_scanner_rounded;
  static const IconData textFields = Icons.text_fields_rounded;

  // ---- Misc ----
  static const IconData currency = Icons.attach_money_rounded;
  static const IconData language = Icons.language_rounded;
  static const IconData theme = Icons.palette_rounded;
  static const IconData about = Icons.info_rounded;
  static const IconData help = Icons.help_outline_rounded;
  static const IconData chevronRight = Icons.chevron_right_rounded;
  static const IconData chevronLeft = Icons.chevron_left_rounded;
  static const IconData expandMore = Icons.expand_more_rounded;
  static const IconData expandLess = Icons.expand_less_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData add = Icons.add_rounded;
  static const IconData remove = Icons.remove_rounded;
  static const IconData copy = Icons.content_copy_rounded;
  static const IconData image = Icons.image_rounded;
  static const IconData refresh = Icons.refresh_rounded;
  static const IconData moreVert = Icons.more_vert_rounded;
  static const IconData moreHoriz = Icons.more_horiz_rounded;
  static const IconData arrowBack = Icons.arrow_back_rounded;
  static const IconData check = Icons.check_rounded;
  static const IconData logo = Icons.auto_awesome_rounded; // placeholder

  /// Returns the category icon for a given category key string.
  ///
  /// Falls back to [other] for unrecognised keys.
  static IconData categoryIcon(String categoryKey) {
    switch (categoryKey.toLowerCase()) {
      case 'meals':
        return meals;
      case 'travel':
        return travel;
      case 'office':
        return office;
      case 'supplies':
        return supplies;
      case 'fuel':
        return fuel;
      case 'lodging':
        return lodging;
      default:
        return other;
    }
  }

  /// Returns the sync-status icon for a given status string.
  static IconData syncStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'synced':
      case 'done':
        return syncDone;
      case 'pending':
      case 'uploading':
        return syncPending;
      case 'failed':
      case 'error':
        return syncFailed;
      case 'offline':
        return syncOffline;
      default:
        return sync;
    }
  }

  /// Returns the storage-provider icon for a given provider key.
  static IconData storageProviderIcon(String providerKey) {
    switch (providerKey.toLowerCase()) {
      case 'google_drive':
      case 'googledrive':
        return googleDrive;
      case 'dropbox':
      case 'onedrive':
      case 'box':
        return cloudStorage;
      case 'local':
      case 'local_encrypted':
        return lock;
      case 'kira_cloud':
      case 'kiracloud':
        return cloud;
      default:
        return storage;
    }
  }
}
