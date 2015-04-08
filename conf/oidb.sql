--
-- Table structure for table `oidb`
--
SET client_encoding = 'UTF8';

CREATE SEQUENCE oidb_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- See http://www.sqlines.com/postgresql/how-to/create_user_defined_type
CREATE DOMAIN rights VARCHAR(12) CHECK (VALUE IN ('public', 'secure', 'proprietary'));

-- oidb table = ObsCore + extensions
CREATE TABLE oidb (
    -- ObsCore model: observation information
    dataproduct_type  text,
    -- TODO 0,1,2,3
    calib_level       integer NOT NULL,
    -- ObsCore model: target information
    target_name       text NOT NULL,
    -- ObsCore model: data description
    obs_id            text,
    obs_collection    text,
    obs_creator_name  text,
    -- ObsCore model: curation information
    obs_release_date  timestamp without time zone DEFAULT now(),
    obs_publisher_did text,
    bib_reference     text,
    data_rights       rights DEFAULT 'public'::text NOT NULL,
    -- ObsCore model: access information
    access_url        text NOT NULL,
    access_format     text,
    access_estsize    bigint,
    -- ObsCore model: spatial characterisation
    s_ra              double precision,
    s_dec             double precision,
    s_fov             real,
    s_region          real,
    s_resolution      real,
    -- ObsCore model: time characterisation
    t_min             real,
    t_max             real,
    t_exptime         real,
    t_resolution      real,
    -- ObsCore model: spectral characterisation
    em_min            real,
    em_max            real,
    em_res_power      real,
    -- ObsCore model: observable axis (left NULL as OIFits contains several observable quantities VIS, VIS2, T3)
    o_ucd             text,
    -- ObsCore model: polarisation axis
    pol_states        text,
    -- ObsCore model: provenance
    facility_name     text,
    instrument_name   text,
    -- OiDB Extension (OIFits metadata)
    instrument_mode   text,
    -- TODO 0,1,2,3,4
    quality_level     integer,
 
    nb_channels       integer NOT NULL,
    nb_vis            integer,
    nb_vis2           integer,
    nb_t3             integer,
    keywords          text,

    subdate           timestamp without time zone DEFAULT now(),
    id                bigint DEFAULT nextval('oidb_id_seq'::regclass) NOT NULL,

    progid            text,
    datapi            text
);

--
-- END
--
