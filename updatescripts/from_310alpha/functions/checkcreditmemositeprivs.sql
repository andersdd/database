CREATE OR REPLACE FUNCTION checkCreditMemoSitePrivs(INTEGER) RETURNS BOOLEAN AS '
DECLARE
  pCmheadid ALIAS FOR $1;
  _check    BOOLEAN;
  _result   INTEGER;

BEGIN

  SELECT COALESCE(usrpref_value::BOOLEAN, false) INTO _check
    FROM usrpref
   WHERE ( (usrpref_username=current_user)
     AND   (usrpref_name=''selectedSites'') );
  IF (NOT _check) THEN
    RETURN true;
  END IF;

  SELECT COALESCE(COUNT(*), 0) INTO _result
    FROM ( SELECT cmitem_id
             FROM cmitem JOIN itemsite ON (itemsite_id=cmitem_itemsite_id)
            WHERE ( (cmitem_cmhead_id=pCmheadid)
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