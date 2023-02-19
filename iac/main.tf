terraform {
  backend "gcs" {}
}

resource "google_project" "starter_project" {
  name       = var.project_name
  project_id = "${random_id.project_random.keepers.project_id}-${random_id.project_random.hex}"
  folder_id = var.app_folder_id

    labels = {
    "firebase" = "enabled"
  }
}

resource "google_firebase_project" "default" {
  provider = google-beta
  project  = google_project.starter_project.project_id
  depends_on = [google_firestore_database.firestore]
}

resource "random_id" "project_random" {
  keepers = {
    project_id = var.project_id
  }

  byte_length = 2
}

resource "google_project_service" "apis" {
  for_each = toset([
    "firebase.googleapis.com",
  ])

  disable_dependent_services=true

  project = google_project.starter_project.project_id
  service = each.key
}

resource "google_project_service" "firestore" {
  provider = google-beta

  for_each = toset([
    "firestore.googleapis.com"
  ])

  disable_dependent_services=true

  project = google_project.starter_project.project_id
  service = each.key

  # Needed for CI tests for permissions to propagate, should not be needed for actual usage
  depends_on = [time_sleep.wait_60_seconds]
}

resource "google_firebase_web_app" "basic" {
    provider = google-beta
    project = google_project.starter_project.project_id
    display_name = "Starter Web App"
    deletion_policy = "DELETE"

    depends_on = [
        google_firebase_project.default,
        google_firestore_database.firestore
    ]
}


data "google_firebase_web_app_config" "basic" {
  provider   = google-beta
  project = google_project.starter_project.project_id
  web_app_id = google_firebase_web_app.basic.app_id
  depends_on = [
    google_firestore_database.firestore
  ]
}


resource "google_firebase_project_location" "basic" {
    provider = google-beta
    project = google_firebase_project.default.project

    location_id = "us-central"
    depends_on = [
        google_firestore_database.firestore
    ]
}

locals {
    tfile = templatefile("${path.module}/templates/firebase.tftpl",
    {
        app_id              = google_firebase_web_app.basic.app_id
        api_key             = data.google_firebase_web_app_config.basic.api_key
        auth_domain         = data.google_firebase_web_app_config.basic.auth_domain
        database_url        = lookup(data.google_firebase_web_app_config.basic, "database_url", "")
        storage_bucket      = lookup(data.google_firebase_web_app_config.basic, "storage_bucket", "")
        messaging_sender_id  = lookup(data.google_firebase_web_app_config.basic, "messaging_sender_id", "")
        measurement_id      = lookup(data.google_firebase_web_app_config.basic, "measurement_id", "")
        project_id = google_project.starter_project.project_id
    })
}

output "tffile" {
    value = local.tfile
}


resource "time_sleep" "wait_60_seconds" {
  depends_on = [google_project.starter_project]

  create_duration = "60s"
}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [google_project_service.firestore["firestore.googleapis.com"]]

  create_duration = "30s"
}

resource "google_firestore_database" "firestore" {
  provider = google-beta

  project = google_project.starter_project.project_id

  name = "(default)"

  location_id = "nam5"
  type        = "FIRESTORE_NATIVE"

  depends_on = [
    google_project_service.apis["firestore.googleapis.com"],
    time_sleep.wait_30_seconds
  ]
}