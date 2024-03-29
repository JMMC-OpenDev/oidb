--
-- Table structure for table `oidb`
--
-- to get whole init sql you can run :
-- $ for s in oidb.sql tap_schema.sql oidb_tap_schema.sql oidb_datalink.sql oidb_datalink_tap_schema.sql; do cat $s >> oidb-init-merged.sql ;  done
-- ( mimic init defined in jmmc-oidb-docker/oidb-postgres/Dockerfile )
--
-- and don't forget to check the id sequence see below.
--
SET client_encoding = 'UTF8';

-- copy doc instead of using BIGSERIAL ( that does not work in my previous (bad?) tests )
CREATE SEQUENCE oidb_id_seq;
-- anyway SEQUENCE val requires to be updated after dump import:
--  SELECT setval('oidb_id_seq', max(id)) FROM oidb; 

-- See http://www.sqlines.com/postgresql/how-to/create_user_defined_type
CREATE DOMAIN rights VARCHAR(12) CHECK (VALUE IN ('public', 'secure', 'proprietary'));

-- oidb table = ObsCore + extensions
CREATE TABLE oidb (
    -- ObsCore model: observation information
    dataproduct_type  text,
    -- TODO 0,1,2,3
    calib_level             integer NOT NULL,
    -- ObsCore model: target information
    target_name             text NOT NULL,
    -- ObsCore model: data description
    obs_id                  text,
    obs_collection          text,
    obs_creator_name        text,
    -- ObsCore model: curation information
    obs_release_date        timestamp without time zone DEFAULT now(),
    obs_publisher_did       text,
    bib_reference           text,
    data_rights             rights DEFAULT 'public'::text NOT NULL,
    -- ObsCore model: access information
    access_url              text NOT NULL,
    access_format           text,
    access_estsize          bigint,
    -- ObsCore model: spatial characterisation
    s_ra                    double precision,
    s_dec                   double precision,
    s_fov                   double precision,
    s_region                double precision,
    s_resolution            double precision,
    -- ObsCore model: time characterisation
    t_min                   double precision,
    t_max                   double precision,
    t_exptime               double precision,
    t_resolution            double precision,
    -- ObsCore model: spectral characterisation
    em_min                  double precision,
    em_max                  double precision,
    em_res_power            double precision,
    -- ObsCore model: observable axis (left NULL as OIFits contains several observable quantities VIS, VIS2, T3)
    o_ucd                   text,
    -- ObsCore model: polarisation axis
    pol_states              text,
    -- ObsCore model: provenance
    facility_name           text,
    instrument_name         text,
    -- OiDB Extension (OIFits metadata)
    instrument_mode         text,
    -- TODO 0,1,2,3,4
    quality_level           integer,

    -- Our extension (we could have put a prefix...) 
    interferometer_stations text,
    nb_channels             integer NOT NULL,
    nb_vis                  integer,
    nb_vis2                 integer,
    nb_t3                   integer,
    keywords                text,

    subdate                 timestamp without time zone DEFAULT now(),
    id                      bigint DEFAULT nextval('oidb_id_seq') PRIMARY KEY,

    progid                  text,
    datapi                  text,

    access_md5              VARCHAR(32)

    -- TODO expose MULTIPLE keyword value for L2/L3
);

-- copy doc instead of using BIGSERIAL ( that does not work in my previous (bad?) tests )
ALTER SEQUENCE oidb_id_seq OWNED BY oidb.id;

-- Create spatial index (pg_sphere required)
CREATE INDEX oidb_spatial ON oidb USING GIST(spoint(radians(s_ra),radians(s_dec)));

-- Limit duplicates on the same collection for a given obs_id and offer UPSERT mode
-- was setup for obsportal incremental sync that can carry updates on past records
-- could be applied on with partitionning / views
CREATE UNIQUE INDEX dup_granule_same_col ON oidb ( obs_id, obs_collection, instrument_mode) WHERE calib_level=0;

--
-- END
--
