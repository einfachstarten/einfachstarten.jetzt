#!/bin/bash

# =============================================================================
# EINFACH STARTEN - PRODUCTION DEPLOYMENT SYSTEM
# deploy-prod.sh - Beta → Production Deployment Script
# =============================================================================

# Konfiguration
BETA_DIR="$HOME/web/beta"
PROD_DIR="$HOME/web"
BACKUP_DIR="$HOME/web/backups"
LOG_FILE="$HOME/web/deployment.log"
GITHUB_TOKEN="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"
GITHUB_REPO="https://einfachstarten:${GITHUB_TOKEN}@github.com/einfachstarten/einfachstarten.jetzt.git"

# Farben für bessere Lesbarkeit
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging-Funktion
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Fehlerbehandlung
error_exit() {
    log "${RED}FEHLER: $1${NC}"
    exit 1
}

# Success-Meldung
success() {
    log "${GREEN}✓ $1${NC}"
}

# Warning-Meldung
warning() {
    log "${YELLOW}⚠ $1${NC}"
}

# Info-Meldung
info() {
    log "${BLUE}ℹ $1${NC}"
}

# =============================================================================
# HAUPTFUNKTIONEN
# =============================================================================

# Voraussetzungen prüfen
check_prerequisites() {
    info "Prüfe Voraussetzungen..."
    
    # Verzeichnisse prüfen
    [ ! -d "$BETA_DIR" ] && error_exit "Beta-Verzeichnis nicht gefunden: $BETA_DIR"
    [ ! -d "$PROD_DIR" ] && error_exit "Produktions-Verzeichnis nicht gefunden: $PROD_DIR"
    
    # Git-Repository prüfen
    cd "$PROD_DIR" || error_exit "Kann nicht in Produktions-Verzeichnis wechseln"
    if [ ! -d ".git" ]; then
        error_exit "Produktions-Verzeichnis ist kein Git-Repository"
    fi
    
    # Backup-Verzeichnis erstellen falls nicht vorhanden
    mkdir -p "$BACKUP_DIR"
    
    success "Alle Voraussetzungen erfüllt"
}

# Beta-Tests durchführen
run_beta_tests() {
    info "Führe Beta-Tests durch..."
    
    # HTML-Validierung
    info "Validiere HTML-Dateien..."
    if command -v tidy >/dev/null 2>&1; then
        for html_file in "$BETA_DIR"/*.html; do
            if [ -f "$html_file" ]; then
                if ! tidy -q -e "$html_file" >/dev/null 2>&1; then
                    warning "HTML-Validierung fehlgeschlagen für: $(basename "$html_file")"
                fi
            fi
        done
    else
        warning "HTML-Validator 'tidy' nicht installiert - überspringe HTML-Validierung"
    fi
    
    # CSS-Validierung
    info "Prüfe CSS-Dateien..."
    for css_file in "$BETA_DIR"/static/*.css; do
        if [ -f "$css_file" ]; then
            # Grundlegende CSS-Syntax-Prüfung
            if ! grep -q "}" "$css_file"; then
                warning "CSS-Datei könnte fehlerhaft sein: $(basename "$css_file")"
            fi
        fi
    done
    
    # Wichtige Dateien prüfen
    info "Prüfe wichtige Dateien..."
    required_files=("index.html" "impressum.html" "static/style.css")
    for file in "${required_files[@]}"; do
        if [ ! -f "$BETA_DIR/$file" ]; then
            error_exit "Wichtige Datei fehlt: $file"
        fi
    done
    
    # Links prüfen (vereinfacht)
    info "Prüfe interne Links..."
    if grep -q "href=\"#" "$BETA_DIR/index.html"; then
        success "Interne Navigation gefunden"
    else
        warning "Keine interne Navigation gefunden"
    fi
    
    success "Beta-Tests abgeschlossen"
}

# Backup der aktuellen Produktion erstellen
create_backup() {
    local backup_name="production_backup_$(date '+%Y%m%d_%H%M%S')"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    info "Erstelle Backup der aktuellen Produktion..."
    
    # Backup erstellen
    cp -r "$PROD_DIR" "$backup_path" || error_exit "Backup-Erstellung fehlgeschlagen"
    
    # Git-Verzeichnis aus Backup entfernen (nicht nötig)
    rm -rf "$backup_path/.git"
    
    # Backup komprimieren
    cd "$BACKUP_DIR" || error_exit "Kann nicht in Backup-Verzeichnis wechseln"
    tar -czf "${backup_name}.tar.gz" "$backup_name" || error_exit "Backup-Komprimierung fehlgeschlagen"
    rm -rf "$backup_name"
    
    # Alte Backups bereinigen (nur die letzten 5 behalten)
    ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm
    
    success "Backup erstellt: ${backup_name}.tar.gz"
}

# Deployment durchführen
deploy_to_production() {
    info "Starte Deployment zur Produktion..."
    
    # Exkludierte Dateien/Verzeichnisse
    exclude_patterns=(
        ".git"
        "*.log"
        "backups"
        "stats"
        "deployment.log"
        "*.bak"
    )
    
    # Rsync-Optionen zusammenbauen
    rsync_excludes=""
    for pattern in "${exclude_patterns[@]}"; do
        rsync_excludes="$rsync_excludes --exclude=$pattern"
    done
    
    # Dateien synchronisieren
    info "Synchronisiere Dateien..."
    eval "rsync -av --delete $rsync_excludes \"$BETA_DIR/\" \"$PROD_DIR/\"" || error_exit "Datei-Synchronisation fehlgeschlagen"
    
    # .htaccess wiederherstellen falls vorhanden
    if [ -f "$BACKUP_DIR/latest_htaccess" ]; then
        cp "$BACKUP_DIR/latest_htaccess" "$PROD_DIR/.htaccess"
        info ".htaccess wiederhergestellt"
    fi
    
    success "Dateien erfolgreich deployed"
}

# Git-Commit und Push
commit_and_push() {
    info "Committe Änderungen zu Git..."
    
    cd "$PROD_DIR" || error_exit "Kann nicht in Produktions-Verzeichnis wechseln"
    
    # Git-Status prüfen
    if [ -z "$(git status --porcelain)" ]; then
        info "Keine Änderungen für Git gefunden"
        return 0
    fi
    
    # Änderungen hinzufügen
    git add . || error_exit "Git add fehlgeschlagen"
    
    # Commit mit aussagekräftiger Nachricht
    local commit_msg="Production deployment $(date '+%Y-%m-%d %H:%M') - Beta to Prod"
    git commit -m "$commit_msg" || error_exit "Git commit fehlgeschlagen"
    
    # Push zu GitHub
    git push "$GITHUB_REPO" main || error_exit "Git push fehlgeschlagen"
    
    success "Änderungen erfolgreich zu GitHub gepusht"
}

# Deployment-Report erstellen
create_deployment_report() {
    local report_file="$BACKUP_DIR/deployment_report_$(date '+%Y%m%d_%H%M%S').txt"
    
    info "Erstelle Deployment-Report..."
    
    cat > "$report_file" << EOF
=============================================================================
EINFACH STARTEN - DEPLOYMENT REPORT
=============================================================================

Deployment-Datum: $(date '+%Y-%m-%d %H:%M:%S')
Beta-Verzeichnis: $BETA_DIR
Produktions-Verzeichnis: $PROD_DIR

DEPLOYMENT-SCHRITTE:
✓ Voraussetzungen geprüft
✓ Beta-Tests durchgeführt
✓ Backup der aktuellen Produktion erstellt
✓ Dateien zur Produktion deployed
✓ Git-Commit und Push durchgeführt

DEPLOYED FILES:
$(cd "$PROD_DIR" && find . -name "*.html" -o -name "*.css" -o -name "*.js" | sort)

BACKUP LOCATION:
Verfügbare Backups in $BACKUP_DIR:
$(ls -la "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "Keine Backups gefunden")

=============================================================================
EOF

    success "Deployment-Report erstellt: $report_file"
}

# Rollback-Funktion
rollback() {
    local latest_backup=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n 1)
    
    if [ -z "$latest_backup" ]; then
        error_exit "Kein Backup für Rollback gefunden"
    fi
    
    warning "ROLLBACK: Stelle letztes Backup wieder her..."
    info "Verwende Backup: $(basename "$latest_backup")"
    
    # Aktuelles Verzeichnis sichern
    mv "$PROD_DIR" "${PROD_DIR}_failed_$(date '+%Y%m%d_%H%M%S')"
    
    # Backup extrahieren
    cd "$(dirname "$PROD_DIR")" || error_exit "Kann nicht in übergeordnetes Verzeichnis wechseln"
    tar -xzf "$latest_backup" || error_exit "Backup-Wiederherstellung fehlgeschlagen"
    
    # Verzeichnis umbenennen
    backup_dir_name=$(basename "$latest_backup" .tar.gz)
    mv "$backup_dir_name" "$(basename "$PROD_DIR")" || error_exit "Verzeichnis-Umbenennung fehlgeschlagen"
    
    success "Rollback erfolgreich durchgeführt"
}

# =============================================================================
# INTERAKTIVE FUNKTIONEN
# =============================================================================

# Benutzer-Bestätigung
confirm_deployment() {
    echo
    info "=== DEPLOYMENT ÜBERSICHT ==="
    echo "Beta-Verzeichnis: $BETA_DIR"
    echo "Ziel-Verzeichnis: $PROD_DIR"
    echo "Backup-Verzeichnis: $BACKUP_DIR"
    echo
    
    # Zeige Unterschiede
    info "Unterschiede zwischen Beta und Produktion:"
    if command -v diff >/dev/null 2>&1; then
        diff -q "$BETA_DIR" "$PROD_DIR" 2>/dev/null | head -10
    fi
    
    echo
    read -p "Möchten Sie das Deployment durchführen? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Deployment abgebrochen"
        exit 0
    fi
}

# =============================================================================
# HAUPTPROGRAMM
# =============================================================================

main() {
    echo
    info "=== EINFACH STARTEN PRODUCTION DEPLOYMENT ==="
    info "Beta → Production Deployment (deploy-prod.sh)"
    echo
    
    # Parameter prüfen
    case "${1:-}" in
        "rollback")
            rollback
            exit 0
            ;;
        "test")
            check_prerequisites
            run_beta_tests
            exit 0
            ;;
        "force")
            # Deployment ohne Benutzer-Bestätigung
            ;;
        *)
            # Interaktiver Modus
            confirm_deployment
            ;;
    esac
    
    # Deployment-Prozess
    check_prerequisites
    run_beta_tests
    create_backup
    deploy_to_production
    commit_and_push
    create_deployment_report
    
    echo
    success "=== DEPLOYMENT ERFOLGREICH ABGESCHLOSSEN ==="
    info "Die Website ist jetzt live unter der Produktions-URL"
    info "Backup verfügbar in: $BACKUP_DIR"
    echo
}

# Fehlerbehandlung aktivieren
set -e
trap 'error_exit "Unerwarteter Fehler in Zeile $LINENO"' ERR

# Hauptprogramm starten
main "$@"