-- =====================================================================
-- TP Révision - Conception relationnelle : la papeterie de Hanta
-- Niveaux 1 et 2 - Étapes 1 à 9 (PostgreSQL)
-- À exécuter dans l'ordre, sur une base vide.
--
-- NB : par rapport à la version précédente (étapes 1 à 5), les données
-- de test des ventes sont ajustées pour que les paiements de l'étape 6
-- (7 000 / 10 000 + 5 000 / 20 000 Ar) ne dépassent jamais le montant dû.
-- =====================================================================


-- =====================================================================
-- ÉTAPE 1 : « Je veux la liste de mes articles avec leur prix. »
-- Schéma : ARTICLE(id_article, libelle, prix_unitaire)  (nouveau)
-- =====================================================================

CREATE TABLE article (
    id_article    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    libelle       VARCHAR(100) NOT NULL,
    prix_unitaire INT NOT NULL CHECK (prix_unitaire >= 0)
);

INSERT INTO article (libelle, prix_unitaire) VALUES
    ('Cahier 100 pages',         1200),
    ('Cahier 200 pages',         2000),
    ('Stylo à bille bleu',        500),
    ('Crayon à papier',           300),
    ('Règle 30 cm',               800),
    ('Manuel Mathématiques CM2', 15000),
    ('Cartable',                35000);

-- Vérification : articles du plus cher au moins cher
SELECT libelle, prix_unitaire
FROM article
ORDER BY prix_unitaire DESC;

-- PIÈGE (étape 1) : quel type pour le prix ? quel identifiant ?
-- Réponse : INT, car les montants sont en ariary sans centimes ; on
-- évite FLOAT/DOUBLE à cause des erreurs d'arrondi. L'identifiant est un
-- numéro généré (clé de substitution) : le libellé peut changer ou être
-- mal saisi, et le code-barres peut manquer ou être réutilisé, alors
-- qu'un numéro généré est unique, stable et jamais NULL.


-- =====================================================================
-- ÉTAPE 2 : « Je range mes articles par rayon. »
-- Schéma :
--   CATEGORIE(id_categorie, libelle)                           (nouveau)
--   ARTICLE(id_article, libelle, prix_unitaire, #id_categorie)  (modifié)
-- =====================================================================

CREATE TABLE categorie (
    id_categorie INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    libelle      VARCHAR(50) NOT NULL UNIQUE
);

INSERT INTO categorie (libelle) VALUES
    ('Cahiers'),
    ('Écriture'),
    ('Géométrie'),
    ('Manuels scolaires'),
    ('Bagagerie'),
    ('Art et loisirs');   -- catégorie vide, pour tester la vérification

-- La table contient déjà des données : colonne facultative d'abord,
-- remplissage, puis NOT NULL.
ALTER TABLE article ADD COLUMN id_categorie INT;

UPDATE article
SET id_categorie = (SELECT id_categorie FROM categorie WHERE libelle = 'Cahiers')
WHERE libelle LIKE 'Cahier%';

UPDATE article
SET id_categorie = (SELECT id_categorie FROM categorie WHERE libelle = 'Écriture')
WHERE libelle IN ('Stylo à bille bleu', 'Crayon à papier');

UPDATE article
SET id_categorie = (SELECT id_categorie FROM categorie WHERE libelle = 'Géométrie')
WHERE libelle = 'Règle 30 cm';

UPDATE article
SET id_categorie = (SELECT id_categorie FROM categorie WHERE libelle = 'Manuels scolaires')
WHERE libelle LIKE 'Manuel%';

UPDATE article
SET id_categorie = (SELECT id_categorie FROM categorie WHERE libelle = 'Bagagerie')
WHERE libelle = 'Cartable';

ALTER TABLE article
    ADD CONSTRAINT fk_article_categorie
    FOREIGN KEY (id_categorie) REFERENCES categorie(id_categorie);

ALTER TABLE article ALTER COLUMN id_categorie SET NOT NULL;
-- (Oracle : ALTER TABLE article MODIFY (id_categorie NOT NULL);)

-- Vérification : nombre d'articles par catégorie, catégories vides incluses
SELECT c.libelle, COUNT(a.id_article) AS nb_articles
FROM categorie c
LEFT JOIN article a ON a.id_categorie = c.id_categorie
GROUP BY c.id_categorie, c.libelle
ORDER BY c.libelle;

-- PIÈGE (étape 2) : pourquoi pas une colonne rayon VARCHAR(50) ?
-- Réponse : du texte libre permet les fautes de frappe ("Cahiers",
-- "cahier", "Cahirs") : un GROUP BY rayon éclate alors un même rayon en
-- plusieurs lignes et les résultats sont faux. Renommer un rayon oblige
-- à modifier tous les articles concernés, et un rayon sans article
-- n'existe pas du tout dans la base.


-- =====================================================================
-- ÉTAPE 3 : « J'enregistre chaque vente : date et heure, quels articles,
-- et combien de chaque. »
-- Schéma :
--   VENTE(id_vente, date_vente_heure)                  (nouveau)
--   LIGNE_VENTE(#id_vente, #id_article, quantite)      (nouveau)
-- =====================================================================

CREATE TABLE vente (
    id_vente         INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_vente_heure TIMESTAMP NOT NULL
);

CREATE TABLE ligne_vente (
    id_vente   INT NOT NULL,
    id_article INT NOT NULL,
    quantite   INT NOT NULL CHECK (quantite > 0),
    PRIMARY KEY (id_vente, id_article),
    CONSTRAINT fk_lv_vente   FOREIGN KEY (id_vente)   REFERENCES vente(id_vente),
    CONSTRAINT fk_lv_article FOREIGN KEY (id_article) REFERENCES article(id_article)
);

INSERT INTO vente (date_vente_heure) VALUES
    ('2026-10-12 09:15'),   -- vente 1
    ('2026-10-12 10:40'),   -- vente 2
    ('2026-10-13 14:05');   -- vente 3

INSERT INTO ligne_vente (id_vente, id_article, quantite) VALUES
    (1, 1, 5), (1, 3, 2), (1, 5, 1),    -- 5 cahiers 100 p. + 2 stylos + 1 règle
    (2, 7, 1),                          -- 1 cartable
    (3, 6, 2), (3, 4, 5);               -- 2 manuels + 5 crayons

-- Vérification : montant total de chaque vente
SELECT v.id_vente,
       v.date_vente_heure,
       SUM(lv.quantite * a.prix_unitaire) AS montant_total
FROM vente v
JOIN ligne_vente lv ON lv.id_vente  = v.id_vente
JOIN article a      ON a.id_article = lv.id_article
GROUP BY v.id_vente, v.date_vente_heure
ORDER BY v.id_vente;
-- Attendu : vente 1 = 7 800 ; vente 2 = 35 000 ; vente 3 = 31 500

-- PIÈGE (étape 3) : où placer la quantité ? pourquoi pas "date" ?
-- Réponse : la quantité dépend du couple (vente, article) : elle va dans
-- la table d'association ligne_vente, ni dans vente (plusieurs articles
-- par vente) ni dans article (plusieurs ventes par article). Le nom
-- "date" est un mot réservé / un type SQL, source de conflits ; de plus
-- il faut aussi l'heure, d'où TIMESTAMP et le nom date_vente_heure.


-- =====================================================================
-- ÉTAPE 4 : « Certains clients reviennent souvent, mais la plupart
-- passent juste acheter un stylo. »
-- Schéma :
--   CLIENT(id_client, nom, type_client, contact?)                  (nouveau)
--   VENTE(id_vente, date_vente_heure, #id_client?)                 (modifié)
-- =====================================================================

CREATE TABLE client (
    id_client   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom         VARCHAR(100) NOT NULL,
    type_client VARCHAR(10)  NOT NULL CHECK (type_client IN ('parent', 'eleve', 'ecole')),
    contact     VARCHAR(20)  UNIQUE
);

INSERT INTO client (nom, type_client, contact) VALUES
    ('Rakoto Jean',      'parent', '034 00 000 01'),
    ('EPP Ambohijatovo', 'ecole',  '020 22 000 02');

-- Clé étrangère facultative : « client de passage » = pas de client (NULL).
ALTER TABLE vente ADD COLUMN id_client INT;

ALTER TABLE vente
    ADD CONSTRAINT fk_vente_client
    FOREIGN KEY (id_client) REFERENCES client(id_client);

UPDATE vente SET id_client = 1 WHERE id_vente = 1;
UPDATE vente SET id_client = 2 WHERE id_vente = 3;
-- la vente 2 reste sans client : client de passage

-- Vérification : ventes avec le nom du client ou « client de passage »
SELECT v.id_vente,
       v.date_vente_heure,
       COALESCE(c.nom, 'client de passage') AS client
FROM vente v
LEFT JOIN client c ON c.id_client = v.id_client
ORDER BY v.id_vente;

-- PIÈGE (étape 4) : la clé étrangère est-elle NOT NULL ? quelle jointure ?
-- Réponse : non, id_client est nullable, car un client de passage n'est
-- pas enregistré. Il faut un LEFT JOIN depuis vente : un INNER JOIN
-- ferait disparaître toutes les ventes sans client.


-- =====================================================================
-- ÉTAPE 5 : « Quel vendeur a fait la vente et sur quelle caisse ? Les
-- commandes par téléphone ne passent par aucune caisse. »
-- Schéma :
--   VENDEUR(id_vendeur, nom)                                       (nouveau)
--   CAISSE(id_caisse, libelle)                                     (nouveau)
--   VENTE(id_vente, date_vente_heure, #id_client?, #id_vendeur,
--         #id_caisse?)                                             (modifié)
-- =====================================================================

CREATE TABLE vendeur (
    id_vendeur INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom        VARCHAR(100) NOT NULL
);

CREATE TABLE caisse (
    id_caisse INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    libelle   VARCHAR(50) NOT NULL UNIQUE
);

INSERT INTO vendeur (nom) VALUES
    ('Mamy Andria'),
    ('Voahangy Rabe');

INSERT INTO caisse (libelle) VALUES
    ('Caisse entrée'),
    ('Caisse rayon manuels');

ALTER TABLE vente ADD COLUMN id_vendeur INT;   -- deviendra obligatoire
ALTER TABLE vente ADD COLUMN id_caisse  INT;   -- reste facultative

UPDATE vente SET id_vendeur = 1, id_caisse = 1    WHERE id_vente = 1;
UPDATE vente SET id_vendeur = 2, id_caisse = 1    WHERE id_vente = 2;
UPDATE vente SET id_vendeur = 2, id_caisse = NULL WHERE id_vente = 3;  -- commande par téléphone

ALTER TABLE vente
    ADD CONSTRAINT fk_vente_vendeur
    FOREIGN KEY (id_vendeur) REFERENCES vendeur(id_vendeur);

ALTER TABLE vente
    ADD CONSTRAINT fk_vente_caisse
    FOREIGN KEY (id_caisse) REFERENCES caisse(id_caisse);

ALTER TABLE vente ALTER COLUMN id_vendeur SET NOT NULL;
-- (Oracle : ALTER TABLE vente MODIFY (id_vendeur NOT NULL);)

-- Vérification : nombre de ventes et chiffre d'affaires par vendeur
SELECT ve.nom,
       COUNT(DISTINCT v.id_vente)                      AS nb_ventes,
       COALESCE(SUM(lv.quantite * a.prix_unitaire), 0) AS chiffre_affaires
FROM vendeur ve
LEFT JOIN vente v        ON v.id_vendeur = ve.id_vendeur
LEFT JOIN ligne_vente lv ON lv.id_vente  = v.id_vente
LEFT JOIN article a      ON a.id_article = lv.id_article
GROUP BY ve.id_vendeur, ve.nom
ORDER BY ve.nom;
-- Attendu : Mamy Andria = 1 vente / 7 800 ; Voahangy Rabe = 2 ventes / 66 500

-- PIÈGE (étape 5) : différence caisse / vente ? lequel est obligatoire ?
-- Réponse : une caisse est un poste physique permanent (un équipement),
-- une vente est un événement ponctuel qui s'y déroule ; une caisse sert
-- à beaucoup de ventes. Le vendeur est obligatoire (NOT NULL), car toute
-- vente est faite par quelqu'un, y compris au téléphone. La caisse est
-- facultative (NULL), car une commande par téléphone ne passe par aucune
-- caisse.


-- =====================================================================
-- ÉTAPE 6 : « On paie en espèces, MVola, Orange Money, chèque. Un parent
-- paie parfois en deux modes, une école en plusieurs fois. »
-- Schéma :
--   MODE_PAIEMENT(id_mode_paiement, libelle)                        (nouveau)
--   PAIEMENT(id_paiement, #id_vente, #id_mode_paiement, montant,
--            date_paiement)                                         (nouveau)
-- =====================================================================

CREATE TABLE mode_paiement (
    id_mode_paiement INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    libelle          VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE paiement (
    id_paiement      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_vente         INT       NOT NULL,
    id_mode_paiement INT       NOT NULL,
    montant          INT       NOT NULL CHECK (montant > 0),
    date_paiement    TIMESTAMP NOT NULL,
    CONSTRAINT fk_paiement_vente FOREIGN KEY (id_vente)         REFERENCES vente(id_vente),
    CONSTRAINT fk_paiement_mode  FOREIGN KEY (id_mode_paiement) REFERENCES mode_paiement(id_mode_paiement)
);

INSERT INTO mode_paiement (libelle) VALUES
    ('Espèces'), ('MVola'), ('Orange Money'), ('Chèque');

INSERT INTO paiement (id_vente, id_mode_paiement, montant, date_paiement) VALUES
    (1, (SELECT id_mode_paiement FROM mode_paiement WHERE libelle = 'Espèces'),  7000, '2026-10-12 09:20'),
    (2, (SELECT id_mode_paiement FROM mode_paiement WHERE libelle = 'MVola'),   10000, '2026-10-12 10:45'),
    (2, (SELECT id_mode_paiement FROM mode_paiement WHERE libelle = 'Espèces'),  5000, '2026-10-12 10:46'),
    (3, (SELECT id_mode_paiement FROM mode_paiement WHERE libelle = 'Chèque'),  20000, '2026-10-14 08:30');

-- Vérification : ventes non soldées (montant dû, payé, reste à payer)
-- Deux sous-requêtes agrégées séparément pour éviter de multiplier les
-- lignes (jointure lignes x paiements).
SELECT t.id_vente,
       t.montant_du,
       COALESCE(p.montant_paye, 0)                  AS montant_paye,
       t.montant_du - COALESCE(p.montant_paye, 0)   AS reste_a_payer
FROM (SELECT lv.id_vente, SUM(lv.quantite * a.prix_unitaire) AS montant_du
      FROM ligne_vente lv
      JOIN article a ON a.id_article = lv.id_article
      GROUP BY lv.id_vente) t
LEFT JOIN (SELECT id_vente, SUM(montant) AS montant_paye
           FROM paiement
           GROUP BY id_vente) p ON p.id_vente = t.id_vente
WHERE t.montant_du - COALESCE(p.montant_paye, 0) > 0
ORDER BY t.id_vente;
-- Attendu : vente 1 = 7 800 / 7 000 / 800 ;
--           vente 2 = 35 000 / 15 000 / 20 000 ;
--           vente 3 = 31 500 / 20 000 / 11 500

-- PIÈGE (étape 6) : pourquoi pas une colonne montant_paye dans vente ?
-- CHECK ou table de référence pour le mode de paiement ?
-- Réponse : une seule colonne ne dit pas COMMENT ni QUAND on a payé :
-- elle ne gère ni les paiements mixtes (MVola + espèces), ni les
-- paiements échelonnés, ni l'historique, et il faut la recalculer à la
-- main. Le mode de paiement va dans une table de référence : ajouter un
-- mode = un INSERT (et non un ALTER sur un CHECK), les libellés restent
-- cohérents et on peut y ajouter des attributs (frais, actif...).


-- =====================================================================
-- ÉTAPE 7 : « Au 15 octobre, le cahier 100 pages passe de 1 200 à 1 500
-- Ar, mais les ventes déjà faites gardent l'ancien prix. »
-- Schéma :
--   HISTORIQUE_PRIX(#id_article, date_debut, prix_unitaire)         (nouveau, bonus)
--   LIGNE_VENTE(#id_vente, #id_article, quantite, prix_unitaire)    (modifié)
--   (ARTICLE.prix_unitaire reste le prix actuel)
-- =====================================================================

-- Bonus : historique de tous les prix de chaque article.
-- Créé et alimenté AVANT l'augmentation, pour garder les anciens prix.
CREATE TABLE historique_prix (
    id_article    INT  NOT NULL,
    date_debut    DATE NOT NULL,
    prix_unitaire INT  NOT NULL CHECK (prix_unitaire >= 0),
    PRIMARY KEY (id_article, date_debut),
    CONSTRAINT fk_hp_article FOREIGN KEY (id_article) REFERENCES article(id_article)
);

INSERT INTO historique_prix (id_article, date_debut, prix_unitaire)
SELECT id_article, DATE '2026-01-01', prix_unitaire FROM article;

-- 7a. L'augmentation du 15 octobre
UPDATE article SET prix_unitaire = 1500 WHERE libelle = 'Cahier 100 pages';

INSERT INTO historique_prix (id_article, date_debut, prix_unitaire)
SELECT id_article, DATE '2026-10-15', 1500 FROM article WHERE libelle = 'Cahier 100 pages';

-- 7b. Constat : on relance la requête de l'étape 3
SELECT v.id_vente,
       v.date_vente_heure,
       SUM(lv.quantite * a.prix_unitaire) AS montant_total
FROM vente v
JOIN ligne_vente lv ON lv.id_vente  = v.id_vente
JOIN article a      ON a.id_article = lv.id_article
GROUP BY v.id_vente, v.date_vente_heure
ORDER BY v.id_vente;
-- CONSTAT : la vente 1 passe de 7 800 à 9 300 Ar (5 cahiers x +300),
-- alors qu'elle date du 12 octobre. Le montant d'une vente passée change
-- avec le prix courant de l'article : c'est faux (et le reste à payer
-- de la vente 1 deviendrait 2 300 au lieu de 800).

-- 7c. Correction : le prix payé est stocké dans la ligne de vente.
ALTER TABLE ligne_vente ADD COLUMN prix_unitaire INT;

-- On reconstitue le prix en vigueur à la date de chaque vente grâce à
-- l'historique (le prix de l'article a déjà changé, on ne peut donc pas
-- le copier depuis article).
UPDATE ligne_vente lv
SET prix_unitaire = (
    SELECT h.prix_unitaire
    FROM historique_prix h
    JOIN vente v ON v.id_vente = lv.id_vente
    WHERE h.id_article = lv.id_article
      AND h.date_debut <= v.date_vente_heure
    ORDER BY h.date_debut DESC
    FETCH FIRST 1 ROW ONLY
);

ALTER TABLE ligne_vente ALTER COLUMN prix_unitaire SET NOT NULL;
ALTER TABLE ligne_vente ADD CONSTRAINT ck_lv_prix CHECK (prix_unitaire >= 0);

-- Nouvelle vente après l'augmentation (au nouveau prix)
INSERT INTO vente (date_vente_heure, id_vendeur, id_caisse)
VALUES ('2026-10-16 08:30', 1, 1);   -- vente 4

INSERT INTO ligne_vente (id_vente, id_article, quantite, prix_unitaire)
SELECT 4, id_article, 2, prix_unitaire FROM article WHERE libelle = 'Cahier 100 pages';

-- Vérification (étape 3 corrigée) : le montant ne change plus jamais
SELECT v.id_vente,
       v.date_vente_heure,
       SUM(lv.quantite * lv.prix_unitaire) AS montant_total
FROM vente v
JOIN ligne_vente lv ON lv.id_vente = v.id_vente
GROUP BY v.id_vente, v.date_vente_heure
ORDER BY v.id_vente;
-- Attendu : vente 1 = 7 800 ; vente 2 = 35 000 ; vente 3 = 31 500 ; vente 4 = 3 000

-- Requête de l'étape 6 mise à jour (à utiliser désormais) :
SELECT t.id_vente,
       t.montant_du,
       COALESCE(p.montant_paye, 0)                AS montant_paye,
       t.montant_du - COALESCE(p.montant_paye, 0) AS reste_a_payer
FROM (SELECT id_vente, SUM(quantite * prix_unitaire) AS montant_du
      FROM ligne_vente
      GROUP BY id_vente) t
LEFT JOIN (SELECT id_vente, SUM(montant) AS montant_paye
           FROM paiement
           GROUP BY id_vente) p ON p.id_vente = t.id_vente
WHERE t.montant_du - COALESCE(p.montant_paye, 0) > 0
ORDER BY t.id_vente;
-- (La requête de l'étape 5 se met à jour de la même façon :
--  SUM(lv.quantite * lv.prix_unitaire), sans jointure sur article.)

-- Prix d'un article à une date donnée, grâce à l'historique :
SELECT h.prix_unitaire
FROM historique_prix h
JOIN article a ON a.id_article = h.id_article
WHERE a.libelle = 'Cahier 100 pages'
  AND h.date_debut <= DATE '2026-10-14'
ORDER BY h.date_debut DESC
FETCH FIRST 1 ROW ONLY;     -- 1 200 ; avec le 2026-10-16, on obtient 1 500

-- PIÈGE (étape 7) : copier le prix dans chaque ligne de vente viole-t-il
-- la 3FN ?
-- Réponse : non, ce n'est pas une redondance : le prix de la ligne est
-- le prix payé à ce moment-là, un fait historique qui dépend de la clé
-- (vente, article), alors que article.prix_unitaire est le prix actuel,
-- un autre fait. Les deux peuvent légitimement différer ; c'est une
-- dénormalisation volontaire et justifiée.


-- =====================================================================
-- ÉTAPE 8 : « Les écoles me donnent leur liste de fournitures par classe.
-- Je veux le coût de la liste de chaque classe. »
-- Schéma :
--   NIVEAU_SCOLAIRE(id_niveau, libelle)                          (nouveau)
--   LISTE_FOURNITURE(#id_niveau, #id_article, quantite)          (nouveau)
-- =====================================================================

CREATE TABLE niveau_scolaire (
    id_niveau INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    libelle   VARCHAR(20) NOT NULL UNIQUE
);

CREATE TABLE liste_fourniture (
    id_niveau  INT NOT NULL,
    id_article INT NOT NULL,
    quantite   INT NOT NULL CHECK (quantite > 0),
    PRIMARY KEY (id_niveau, id_article),
    CONSTRAINT fk_lf_niveau  FOREIGN KEY (id_niveau)  REFERENCES niveau_scolaire(id_niveau),
    CONSTRAINT fk_lf_article FOREIGN KEY (id_article) REFERENCES article(id_article)
);

INSERT INTO niveau_scolaire (libelle) VALUES ('CP'), ('CE1'), ('CM2'), ('6e');

-- CP et CM2 : données de l'énoncé. CE1 et 6e : données de test inventées.
INSERT INTO liste_fourniture (id_niveau, id_article, quantite)
SELECT n.id_niveau, a.id_article, x.quantite
FROM (VALUES
    ('CP',  'Cahier 100 pages',          6),
    ('CP',  'Crayon à papier',           4),
    ('CP',  'Stylo à bille bleu',        2),
    ('CE1', 'Cahier 100 pages',          5),
    ('CE1', 'Crayon à papier',           4),
    ('CE1', 'Stylo à bille bleu',        2),
    ('CE1', 'Règle 30 cm',               1),
    ('CM2', 'Cahier 100 pages',          4),
    ('CM2', 'Cahier 200 pages',          2),
    ('CM2', 'Stylo à bille bleu',        4),
    ('CM2', 'Règle 30 cm',               1),
    ('CM2', 'Manuel Mathématiques CM2',  1),
    ('6e',  'Cahier 200 pages',          3),
    ('6e',  'Stylo à bille bleu',        4),
    ('6e',  'Règle 30 cm',               1)
) AS x(niveau, article, quantite)
JOIN niveau_scolaire n ON n.libelle = x.niveau
JOIN article a         ON a.libelle = x.article;

-- Vérification : coût de chaque liste au prix actuel
SELECT n.libelle AS niveau,
       SUM(lf.quantite * a.prix_unitaire) AS cout_liste
FROM niveau_scolaire n
JOIN liste_fourniture lf ON lf.id_niveau  = n.id_niveau
JOIN article a           ON a.id_article  = lf.id_article
GROUP BY n.id_niveau, n.libelle
ORDER BY n.id_niveau;
-- Attendu (cahier 100 p. à 1 500) : CP = 11 200 ; CE1 = 10 500 ;
--                                   CM2 = 27 800 ; 6e = 8 800

-- PIÈGE (étape 8) : pourquoi pas une colonne liste VARCHAR(500) ?
-- Réponse : du texte libre n'est pas exploitable par SQL : impossible de
-- calculer le coût, de savoir quelles classes utilisent un article, ou
-- de garantir que l'article existe (pas de clé étrangère) ; la valeur
-- viole aussi la 1FN (plusieurs valeurs dans une même cellule). La liste
-- est une table d'association (niveau, article) porteuse de la quantité.


-- =====================================================================
-- ÉTAPE 9 : « Je vends un Pack Écolier à 8 000 Ar : 5 cahiers 100 pages,
-- 2 stylos et une règle. Le pack se vend comme un article. »
-- Schéma :
--   COMPOSITION_ARTICLE(#id_pack, #id_composant, quantite)   (nouveau)
--   (le pack est une ligne de ARTICLE, dans une nouvelle catégorie)
-- =====================================================================

-- Association réflexive sur article, porteuse de la quantité.
CREATE TABLE composition_article (
    id_pack       INT NOT NULL,
    id_composant  INT NOT NULL,
    quantite      INT NOT NULL CHECK (quantite > 0),
    PRIMARY KEY (id_pack, id_composant),
    CONSTRAINT fk_ca_pack      FOREIGN KEY (id_pack)      REFERENCES article(id_article),
    CONSTRAINT fk_ca_composant FOREIGN KEY (id_composant) REFERENCES article(id_article),
    CONSTRAINT ck_ca_pas_soi_meme CHECK (id_pack <> id_composant)
);

INSERT INTO categorie (libelle) VALUES ('Packs rentrée');

INSERT INTO article (libelle, prix_unitaire, id_categorie)
SELECT 'Pack Écolier', 8000, id_categorie FROM categorie WHERE libelle = 'Packs rentrée';

-- Le pack a aussi un prix initial dans l'historique
INSERT INTO historique_prix (id_article, date_debut, prix_unitaire)
SELECT id_article, DATE '2026-10-16', 8000 FROM article WHERE libelle = 'Pack Écolier';

INSERT INTO composition_article (id_pack, id_composant, quantite)
SELECT p.id_article, c.id_article, x.quantite
FROM (VALUES
    ('Cahier 100 pages',   5),
    ('Stylo à bille bleu', 2),
    ('Règle 30 cm',        1)
) AS x(composant, quantite)
JOIN article p ON p.libelle = 'Pack Écolier'
JOIN article c ON c.libelle = x.composant;

-- Vérification : prix du pack, prix au détail, économie du client
SELECT p.libelle                                  AS pack,
       p.prix_unitaire                            AS prix_pack,
       SUM(ca.quantite * c.prix_unitaire)         AS prix_detail,
       SUM(ca.quantite * c.prix_unitaire) - p.prix_unitaire AS economie
FROM article p
JOIN composition_article ca ON ca.id_pack      = p.id_article
JOIN article c              ON c.id_article    = ca.id_composant
GROUP BY p.id_article, p.libelle, p.prix_unitaire;
-- Attendu : Pack Écolier = 8 000 / 9 300 / 1 300 Ar d'économie
-- (5 x 1 500 + 2 x 500 + 1 x 800 = 9 300)

-- PIÈGE (étape 9) : pourquoi pas une table pack séparée ? quelle
-- contrainte empêche un pack de se contenir lui-même ?
-- Réponse : le pack doit se vendre comme un article : s'il était dans
-- une autre table, il faudrait dupliquer ligne_vente, les catégories,
-- l'historique de prix et toutes les requêtes. Un pack est donc un
-- article, et la composition est une association réflexive. La
-- contrainte CHECK (id_pack <> id_composant) interdit qu'un pack se
-- contienne directement lui-même ; les cycles indirects (A contient B
-- qui contient A) demandent un trigger ou un contrôle applicatif.


-- =====================================================================
-- SCHÉMA RELATIONNEL FINAL (pour schema.md)
--   CATEGORIE(id_categorie, libelle)
--   ARTICLE(id_article, libelle, prix_unitaire, #id_categorie)
--   HISTORIQUE_PRIX(#id_article, date_debut, prix_unitaire)
--   CLIENT(id_client, nom, type_client, contact?)
--   VENDEUR(id_vendeur, nom)
--   CAISSE(id_caisse, libelle)
--   VENTE(id_vente, date_vente_heure, #id_client?, #id_vendeur, #id_caisse?)
--   LIGNE_VENTE(#id_vente, #id_article, quantite, prix_unitaire)
--   MODE_PAIEMENT(id_mode_paiement, libelle)
--   PAIEMENT(id_paiement, #id_vente, #id_mode_paiement, montant, date_paiement)
--   NIVEAU_SCOLAIRE(id_niveau, libelle)
--   LISTE_FOURNITURE(#id_niveau, #id_article, quantite)
--   COMPOSITION_ARTICLE(#id_pack, #id_composant, quantite)
-- =====================================================================
