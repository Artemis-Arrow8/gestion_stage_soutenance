-- Suppression préalable pour les tests (ordre inverse des dépendances)
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