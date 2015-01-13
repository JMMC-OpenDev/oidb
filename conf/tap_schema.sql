--
-- TAP_SCHEMA structure
-- 
-- Note: use the oidb user to execute this script (Owner = oidb):
--   psql -U oidb oidb < tap_schema.sql
--

SET client_encoding = 'UTF8';


--
-- Drop Schema first --
--

ALTER TABLE ONLY "TAP_SCHEMA"."key_columns" DROP CONSTRAINT "key_columns_fkey";
ALTER TABLE ONLY "TAP_SCHEMA"."keys" DROP CONSTRAINT "keys_pkey";
ALTER TABLE ONLY "TAP_SCHEMA"."keys" DROP CONSTRAINT "keys_fkey_from";
ALTER TABLE ONLY "TAP_SCHEMA"."keys" DROP CONSTRAINT "keys_fkey_target";
ALTER TABLE ONLY "TAP_SCHEMA"."columns" DROP CONSTRAINT "columns_pkey";
ALTER TABLE ONLY "TAP_SCHEMA"."columns" DROP CONSTRAINT "columns_fkey";
ALTER TABLE ONLY "TAP_SCHEMA"."tables" DROP CONSTRAINT "tables_pkey";
ALTER TABLE ONLY "TAP_SCHEMA"."tables" DROP CONSTRAINT "tables_fkey";
ALTER TABLE ONLY "TAP_SCHEMA"."schemas" DROP CONSTRAINT "schemas_pkey";

DROP TABLE "TAP_SCHEMA"."key_columns";
DROP TABLE "TAP_SCHEMA"."keys";
DROP TABLE "TAP_SCHEMA"."columns";
DROP TABLE "TAP_SCHEMA"."tables";
DROP TABLE "TAP_SCHEMA"."schemas";
DROP SCHEMA "TAP_SCHEMA";


--
-- Create Schema with tables
--

CREATE SCHEMA "TAP_SCHEMA";


CREATE TABLE "TAP_SCHEMA"."schemas" (
    "schema_name" character varying NOT NULL,
    "description" character varying,
    "utype" character varying
);

ALTER TABLE ONLY "TAP_SCHEMA"."schemas"
    ADD CONSTRAINT "schemas_pkey" PRIMARY KEY ("schema_name");


CREATE TABLE "TAP_SCHEMA"."tables" (
    "schema_name" character varying NOT NULL,
    "table_name" character varying NOT NULL,
    "table_type" character varying,
    "description" character varying,
    "utype" character varying
);

-- PK should be created on (schema_name, table_name) but columns do not have the schema_name column !!
ALTER TABLE ONLY "TAP_SCHEMA"."tables"
    ADD CONSTRAINT "tables_pkey" PRIMARY KEY ("table_name");
ALTER TABLE ONLY "TAP_SCHEMA"."tables"
    ADD CONSTRAINT "tables_fkey" FOREIGN KEY ("schema_name") REFERENCES "TAP_SCHEMA"."schemas" ("schema_name");


CREATE TABLE "TAP_SCHEMA"."columns" (
    "table_name" character varying NOT NULL,
    "column_name" character varying NOT NULL,
    "description" character varying,
    "unit" character varying,
    "ucd" character varying,
    "utype" character varying,
    "datatype" character varying,
    "size" integer,
    "principal" integer,
    "indexed" integer,
    "std" integer
);

ALTER TABLE ONLY "TAP_SCHEMA"."columns"
    ADD CONSTRAINT "columns_pkey" PRIMARY KEY ("table_name","column_name");
ALTER TABLE ONLY "TAP_SCHEMA"."columns"
    ADD CONSTRAINT "columns_fkey" FOREIGN KEY ("table_name") REFERENCES "TAP_SCHEMA"."tables" ("table_name");


CREATE TABLE "TAP_SCHEMA"."keys" (
    "key_id" character varying NOT NULL,
    "from_table" character varying,
    "target_table" character varying,
    "description" character varying,
    "utype" character varying
);

ALTER TABLE ONLY "TAP_SCHEMA"."keys"
    ADD CONSTRAINT "keys_pkey" PRIMARY KEY ("key_id");
ALTER TABLE ONLY "TAP_SCHEMA"."keys"
    ADD CONSTRAINT "keys_fkey_from" FOREIGN KEY ("from_table") REFERENCES "TAP_SCHEMA"."tables" ("table_name");
ALTER TABLE ONLY "TAP_SCHEMA"."keys"
    ADD CONSTRAINT "keys_fkey_target" FOREIGN KEY ("target_table") REFERENCES "TAP_SCHEMA"."tables" ("table_name");


CREATE TABLE "TAP_SCHEMA"."key_columns" (
    "key_id" character varying NOT NULL,
    "from_column" character varying,
    "target_column" character varying
);

ALTER TABLE ONLY "TAP_SCHEMA"."key_columns"
    ADD CONSTRAINT "key_columns_fkey" FOREIGN KEY ("key_id") REFERENCES "TAP_SCHEMA"."keys" ("key_id");

--
-- Data
--

INSERT INTO "TAP_SCHEMA"."schemas" VALUES 
('TAP_SCHEMA', 'Set of tables listing and describing the schemas, tables and columns published in this TAP service.', NULL);

-- Tables
INSERT INTO "TAP_SCHEMA"."tables" VALUES 
('TAP_SCHEMA', 'schemas', 'table', 'List of schemas published in this TAP service.', NULL),
('TAP_SCHEMA', 'tables', 'table', 'List of tables published in this TAP service.', NULL),
('TAP_SCHEMA', 'keys', 'table', 'List all foreign keys but provides just the tables linked by the foreign key. To know which columns of these tables are linked, see in TAP_SCHEMA.key_columns using the key_id.', NULL),
('TAP_SCHEMA', 'key_columns', 'table', 'List all foreign keys but provides just the columns linked by the foreign key. To know the table of these columns, see in TAP_SCHEMA.keys using the key_id.', NULL),
('TAP_SCHEMA', 'columns', 'table', 'List of columns of all tables listed in TAP_SCHEMA.TABLES and published in this TAP service.', NULL)
;

-- Table Columns
INSERT INTO "TAP_SCHEMA"."columns" VALUES 
('schemas', 'schema_name', 'schema name, possibly qualified', NULL, NULL, NULL, 'VARCHAR', -1, 1, 1, 1),
('schemas', 'description', 'brief description of schema', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1),
('schemas', 'utype', 'UTYPE if schema corresponds to a data model', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1);

INSERT INTO "TAP_SCHEMA"."columns" VALUES 
('tables', 'schema_name', 'the schema name from TAP_SCHEMA.schemas', NULL, NULL, NULL, 'VARCHAR', -1, 1, 1, 1),
('tables', 'table_name', 'table name as it should be used in queries', NULL, NULL, NULL, 'VARCHAR', -1, 1, 1, 1),
('tables', 'table_type', 'one of: table, view', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1),
('tables', 'description', 'brief description of table', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1),
('tables', 'utype', 'UTYPE if table corresponds to a data model', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1);

INSERT INTO "TAP_SCHEMA"."columns" VALUES 
('keys', 'key_id', 'unique key identifier', NULL, NULL, NULL, 'VARCHAR', -1, 1, 1, 1),
('keys', 'from_table', 'fully qualified table name', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1),
('keys', 'target_table', 'fully qualified table name', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1),
('keys', 'description', 'description of this key', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1),
('keys', 'utype', 'utype of this key', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1);

INSERT INTO "TAP_SCHEMA"."columns" VALUES 
('key_columns', 'key_id', 'unique key identifier', NULL, NULL, NULL, 'VARCHAR', -1, 1, 1, 1),
('key_columns', 'from_column', 'key column name in the from_table', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1),
('key_columns', 'target_column', 'key column name in the target_table', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1);

INSERT INTO "TAP_SCHEMA"."columns" VALUES 
('columns', 'table_name', 'table name from TAP_SCHEMA.tables', NULL, NULL, NULL, 'VARCHAR', -1, 1, 1, 1),
('columns', 'column_name', 'column name', NULL, NULL, NULL, 'VARCHAR', -1, 1, 1, 1),
('columns', 'description', 'brief description of column', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1),
('columns', 'unit', 'unit in VO standard format', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1),
('columns', 'ucd', 'UCD of column if any', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1),
('columns', 'utype', 'UTYPE of column if any', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1),
('columns', 'datatype', 'ADQL datatype as in section 2.5', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 1),
('columns', 'size', 'length of variable length datatypes', NULL, NULL, NULL, 'INTEGER', -1, 0, 0, 1),
('columns', 'principal', 'a principal column; 1 means true, 0 means false', NULL, NULL, NULL, 'INTEGER', -1, 0, 0, 1),
('columns', 'indexed', 'an indexed column; 1 means true, 0 means false', NULL, NULL, NULL, 'INTEGER', -1, 0, 0, 1),
('columns', 'std', 'a standard column; 1 means true, 0 means false', NULL, NULL, NULL, 'INTEGER', -1, 0, 0, 1);

--
-- END
--
