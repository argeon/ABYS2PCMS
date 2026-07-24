CREATE TABLE LS_FLAT AS
SELECT
    ff.FLAT_NUMBER            AS FLATNR,
    CAST(1 AS INT)                                         AS FLATDEFN,
   ff.FLOOR_NUMBER                                         AS FLOOR_NUMBER,
    CAST(ff.BUILDING_DOOR_CODE AS INT)                     AS BNA_ID,
    CAST(4102 AS INT)                                      AS ENT_ID,
    ff.TYPE,
    ff.ADDRESS_NUMBER,
    ff.NATIONAL_CODE,
    ff.BUILDING_DOOR_ID,
    bd.CODE                                                AS ABYS_BUILDING_DOOR_CODE,
    bd.ID                                                  AS ABYS_BUILDING_DOOR_ID,
    agr.SUBSCRIBER_TYPE_ID                                 AS ABYS_SUBSCRIBER_TYPE_ID,
    i.ID                                                   AS ABYS_INSTALLATION_ID,
    i.STATUS                                               AS ABYS_INSTALLATION_GSTATUS,
    i.FIRST_STARTUP_DATE                                   AS ABYS_STARTUP_DATE_RAW,
    i.INSTALLATION_STATUS_ID                               AS ABYS_INSTALLATION_STATUS_ID,
    i.INSTALLATION_CANCEL_DATE                             AS ABYS_INSTALLATION_CANCELDATE,
    ff.CREATED_TIMESTAMP                                   AS FLAT_CREATED_TIMESTAMP,
    ff.CREATED_USER_ID                                     AS FLAT_CREATED_USER_ID,
    ff.UPDATED_TIMESTAMP                                   AS FLAT_UPDATED_TIMESTAMP,
    ff.UPDATED_USER_ID                                     AS FLAT_UPDATED_USER_ID,
    ff.ID                                                  AS ABYS_FLAT_ID,
    ff.FLAT_NUMBER                                         AS FLAT_NUMBER_RAW
FROM GIS_BUILDING_FLAT ff
INNER JOIN GIS_BUILDING_DOOR bd
    ON bd.ID = ff.BUILDING_DOOR_ID
LEFT JOIN CS_SUBSCRIBER agr
    ON ff.ID = agr.BUILDING_FLAT_ID
LEFT JOIN CS_INSTALLATION i
    ON agr.ID = i.SUBSCRIBER_ID
    