CREATE OR REPLACE FUNCTION checkRASitePrivs(INTEGER) RETURNS BOOLEAN AS '
DECLARE
  pRaheadid ALIAS FOR $1;
  _check    BOOLEAN;
  _result   INTEGER;

BEGIN
  SELECT COALESCE(COUNT(*), 0) INTO _result
    FROM ( SELECT raitem_id
             FROM raitem, itemsite
            WHERE ( (raitem_rahead_id=pRaheadid)
              AND   (raitem_itemsite_id=itemsite_id)
              AND   (itemsite_warehous_id NOT IN (SELECT usrsite_warehous_id
                                                    FROM usrsite
                                                   WHERE (usrsite_username=current_user))) )
           UNION
           SELECT raitem_id
             FROM raitem, itemsite
            WHERE ( (raitem_rahead_id=pRaheadid)
              AND   (raitem_coitem_itemsite_id=itemsite_id)
              AND   (itemsite_warehous_id NOT IN (SELECT usrsite_warehous_id
                                                  FROM usrsite
                                                 WHERE (usrsite_username=current_user))) )
         ) AS data;
  IF (_result > 0) THEN
    RETURN false;
  END IF;

  RETURN true;
END;
' LANGUAGE 'plpgsql';