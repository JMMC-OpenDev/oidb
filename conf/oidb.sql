--
-- Table structure for table `oidata`
--

DROP TABLE IF EXISTS `oidata`;
CREATE TABLE `oidata` (
  -- ObsCore model: observation information
  `dataproduct_type` VARCHAR(128) DEFAULT 'OpticalInterferometryData',
  `calib_level`      INT          NOT NULL                           COMMENT 'Calibration level',
  -- ObsCore model: target information
  `target_name`      TEXT         NULL                               COMMENT 'Target identifier',
  -- ObsCore model: data description
  `obs_id`           TEXT         NULL,
  `obs_collection`   TEXT         NULL                               COMMENT 'Name of the data collection',
  `obs_creator_name` TEXT         NULL                               COMMENT 'Name of the creator of the data',
  -- ObsCore model: curation information
  `obs_release_date` TIMESTAMP    NULL                               COMMENT 'Release date',
  `obs_published_did` TEXT        NULL,
  `bib_reference`    TEXT         NULL                               COMMENT 'Bibliographic reference',
  `data_rights`      ENUM("public","secure","proprietary") NOT NULL  COMMENT 'Data rights',
  -- ObsCore model: access information
  `access_url`       VARCHAR(256) NOT NULL                           COMMENT 'URL of the source OIFits file',
  `access_format`    TEXT         NULL,
  `access_estsize`   INT          NULL                               COMMENT 'Estimated size of dataset in kb',
  -- ObsCore model: spatial characterisation
  `s_ra`             DOUBLE       NOT NULL                           COMMENT 'R.A. at mean equinox',
  `s_dec`            DOUBLE       NOT NULL                           COMMENT 'Decl. at mean equinox',
  `s_fov`            DOUBLE       NULL                               COMMENT 'TBD',
  `s_region`         TEXT         NULL                               COMMENT 'TBD',
  `s_resolution`     FLOAT        NULL                               COMMENT 'TBD',
  -- ObsCore model: time characterisation
  `t_min`            DOUBLE       NOT NULL                           COMMENT 'Minimal Modified Julian Date',
  `t_max`            DOUBLE       NOT NULL                           COMMENT 'Maximal Modified Julian Date',
  `t_exptime`        FLOAT        NOT NULL                           COMMENT 'Integration time',
  `t_resolution`     FLOAT        NULL                               COMMENT 'TBD',
  -- ObsCore model: spectral characterisation
  `em_min`           DOUBLE       NOT NULL                           COMMENT 'Min wavelength with value for the target',
  `em_max`           DOUBLE       NOT NULL                           COMMENT 'Max wavelength with value for the target',
  `em_res_power`     DOUBLE       NOT NULL                           COMMENT 'Spectral resolving power',
  -- ObsCore model: observable axis
  `o_ucd`            TEXT         NULL                               COMMENT 'UCD of observable',
  -- ObsCore model: polarisation axis
  `pol_states`       TEXT         NULL                               COMMENT 'N/A',
  -- ObsCore model: provenance
  `facility_name`    TEXT         NOT NULL                           COMMENT 'Facility of the instrument',
  `instrument_name`  TEXT         NOT NULL                           COMMENT 'Name of the instrument',

  -- OIFits metadata
  `nb_channels`      INT          NOT NULL                           COMMENT '',
  `nb_vis`           INT          NOT NULL                           COMMENT 'Count of VIS values for the target',
  `nb_vis2`          INT          NOT NULL                           COMMENT 'Count of VIS2 values for the target',
  `nb_t3`            INT          NOT NULL                           COMMENT 'Count of T3 values for the target',

  `subdate`          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Date of submission'
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
