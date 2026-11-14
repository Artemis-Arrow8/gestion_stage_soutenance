-- DEPRECATED: les migrations Django font autorité pour le schéma.
-- Ce script est destructif (il supprime des tables) et ne doit pas être exécuté.
-- Utiliser `python manage.py migrate` après avoir sauvegardé toute base existante.

-- Suppression préalable pour les tests (ordre inverse des dépendances)
DROP TABLE IF EXISTS room CASCADE;
DROP TABLE IF EXISTS assessment CASCADE;
DROP TABLE IF EXISTS resource_booking CASCADE;
DROP TABLE IF EXISTS defense CASCADE;
DROP TABLE IF EXISTS jury_member CASCADE;
DROP TABLE IF EXISTS jury CASCADE;
DROP TABLE IF EXISTS review CASCADE;
DROP TABLE IF EXISTS document_version CASCADE;
DROP TABLE IF EXISTS internship_folder CASCADE;
DROP TABLE IF EXISTS student CASCADE;
DROP TABLE IF EXISTS campaign CASCADE;

-- 1. Table Campagne
CREATE TABLE campaign (
    id SERIAL PRIMARY KEY,
    academic_year VARCHAR(50) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. Table Étudiant
CREATE TABLE student (
    id SERIAL PRIMARY KEY,
    student_number VARCHAR(100) UNIQUE NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL
);
-- ==========================================
-- Liaison entre compte utilisateur et étudiant
-- ==========================================

CREATE TABLE IF NOT EXISTS student_account (
    id SERIAL PRIMARY KEY,

    user_id INTEGER NOT NULL UNIQUE
        REFERENCES auth_user(id)
        ON DELETE CASCADE,

    student_id INTEGER NOT NULL UNIQUE
        REFERENCES student(id)
        ON DELETE CASCADE
);

-- 3. Table Dossier de Stage
CREATE TABLE internship_folder (
    id SERIAL PRIMARY KEY,
    student_id INT REFERENCES student(id) ON DELETE CASCADE,
    campaign_id INT REFERENCES campaign(id) ON DELETE CASCADE,
    company_name VARCHAR(255) NOT NULL,
    subject TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'brouillon',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Affectations nominatives : un encadreur ne consulte que les dossiers liés.
CREATE TABLE IF NOT EXISTS folder_supervisor (
    id BIGSERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES auth_user(id) ON DELETE CASCADE,
    folder_id BIGINT NOT NULL REFERENCES internship_folder(id) ON DELETE CASCADE,
    CONSTRAINT unique_supervisor_folder_assignment UNIQUE (user_id, folder_id)
);

-- 4. Table Version de Document (Rapports)
CREATE TABLE document_version (
    id SERIAL PRIMARY KEY,
    folder_id INT REFERENCES internship_folder(id) ON DELETE CASCADE,
    version_number INT NOT NULL,
    file_path VARCHAR(255) NOT NULL,
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. Table Avis (Encadreur / Tuteur)
CREATE TABLE review (
    id SERIAL PRIMARY KEY,
    document_version_id INT REFERENCES document_version(id) ON DELETE CASCADE,
    author_id INT REFERENCES auth_user(id) ON DELETE SET NULL,
    author_role VARCHAR(50) NOT NULL, -- 'encadreur' ou 'tuteur'
    decision VARCHAR(50) NOT NULL,    -- 'favorable' ou 'defavorable'
    comments TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 6. Table Jury
CREATE TABLE jury (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    is_complete BOOLEAN DEFAULT FALSE
);

-- 7. Table Membre du Jury
CREATE TABLE jury_member (
    id SERIAL PRIMARY KEY,
    jury_id INT REFERENCES jury(id) ON DELETE CASCADE,
    member_name VARCHAR(255) NOT NULL,
    role_in_jury VARCHAR(100) NOT NULL -- 'president', 'rapporteur', 'examinateur'
);

CREATE TABLE IF NOT EXISTS jury_member_account (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE REFERENCES auth_user(id) ON DELETE CASCADE,
    jury_member_id INTEGER NOT NULL UNIQUE
        REFERENCES jury_member(id) ON DELETE CASCADE
);

-- 8. Table Soutenance
CREATE TABLE defense (
    id SERIAL PRIMARY KEY,
    folder_id INT REFERENCES internship_folder(id) ON DELETE CASCADE,
    jury_id INT REFERENCES jury(id) ON DELETE SET NULL,
    room_name VARCHAR(100) NOT NULL,
    slot_range TSTZRANGE NOT NULL, -- Intervalle de temps (Début, Fin)
    status VARCHAR(50) DEFAULT 'planifie'
);

-- 9. Table Évaluation et Notes
CREATE TABLE assessment (
    id SERIAL PRIMARY KEY,
    defense_id INT REFERENCES defense(id) ON DELETE CASCADE,
    report_grade DECIMAL(5,2) CHECK (report_grade >= 0 AND report_grade <= 20),
    oral_grade DECIMAL(5,2) CHECK (oral_grade >= 0 AND oral_grade <= 20),
    final_average DECIMAL(5,2) CHECK (final_average >= 0 AND final_average <= 20),
    is_approved BOOLEAN DEFAULT FALSE
);

-- NOTE TECHNIQUE IMPORTANTE (Règle EXG01) :
-- Pour garantir qu'une salle ou un jury ne soit jamais réservé sur deux créneaux qui se chevauchent, 
-- PostgreSQL permet d'utiliser une extension et une contrainte d'exclusion (GIST) sur les tstzrange.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Contrainte d'exclusion pour empêcher les doubles réservations de salles
ALTER TABLE defense
ADD CONSTRAINT prevent_room_double_booking 
EXCLUDE USING gist (room_name WITH =, slot_range WITH &&);

-- Contrainte d'exclusion pour empêcher qu'un même jury soit affecté sur deux soutenances en même temps
ALTER TABLE defense
ADD CONSTRAINT prevent_jury_double_booking 
EXCLUDE USING gist (jury_id WITH =, slot_range WITH &&);

-- =============================================================
-- 10. Table Salle — AJOUT TÂCHE 4 (module planification)
--     Catalogue des salles de soutenance. La table `defense` reste
--     liée à la salle via `room_name` (identifiant textuel), ce qui
--     préserve les contraintes EXG01 existantes ; le serveur Django
--     vérifie que la salle existe et est active avant planification.
-- =============================================================
CREATE TABLE IF NOT EXISTS room (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    capacity INT NOT NULL CHECK (capacity > 0),
    is_active BOOLEAN DEFAULT TRUE
);

-- Salles de démonstration (ignorées si elles existent déjà)
INSERT INTO room (name, capacity, is_active) VALUES
    ('Amphithéâtre A', 120, TRUE),
    ('Salle 101', 30, TRUE),
    ('Salle 102', 30, TRUE),
    ('Salle 103', 25, TRUE)
ON CONFLICT (name) DO NOTHING;