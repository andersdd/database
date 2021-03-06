CREATE OR REPLACE FUNCTION postCountTagLocation(INTEGER, BOOLEAN) RETURNS INTEGER AS '
DECLARE
  pInvcntid ALIAS FOR $1;
  pThaw ALIAS FOR $2;
  _invhistid INTEGER;
  _postDate TIMESTAMP;
  _runningQty NUMERIC;
  _errorCode INTEGER;
  _itemlocSeries INTEGER;
  _hasDetail BOOLEAN;
  _p RECORD;
  _itemloc RECORD;
  _cntslip RECORD;
  _origLocQty NUMERIC;
BEGIN

  SELECT invcnt_id, invcnt_tagnumber, invcnt_qoh_after,
         invcnt_location_id, invcnt_tagdate,
         item_number,
         itemsite_id, itemsite_freeze,
         itemsite_qtyonhand,
         itemsite_loccntrl, COALESCE(invcnt_location_id, -1) AS itemsite_location_id,
         stdcost(itemsite_item_id) AS cost,
         itemsite_controlmethod INTO _p
  FROM invcnt, itemsite, item
  WHERE ( (invcnt_itemsite_id=itemsite_id)
   AND (itemsite_item_id=item_id)
   AND (invcnt_qoh_after IS NOT NULL)
   AND (NOT invcnt_posted)
   AND (invcnt_id=pInvcntid) );
  IF (NOT FOUND) THEN
    RETURN -9;
  END IF;

  SELECT COALESCE(SUM(itemloc_qty),0.0) INTO _origLocQty
    FROM itemloc
   WHERE ((itemloc_itemsite_id=_p.itemsite_id)
     AND  (itemloc_location_id=_p.invcnt_location_id));
  IF (NOT FOUND) THEN
    _origLocQty := 0.0;
  END IF;

  SELECT NEXTVAL(''invhist_invhist_id_seq'') INTO _invhistid;

  IF (_p.itemsite_freeze) THEN
    _postDate := _p.invcnt_tagdate;
  ELSE
    _postDate := CURRENT_TIMESTAMP;
  END IF;

  _hasDetail = FALSE;

--  Post the detail indicated by cntslips
  IF ( (_p.itemsite_loccntrl) OR
       (_p.itemsite_controlmethod IN (''L'', ''S'')) ) THEN

    SELECT NEXTVAL(''itemloc_series_seq'') INTO _itemlocSeries;

--  Adjust any existing detail to 0
    FOR _itemloc IN SELECT itemloc_id, itemloc_location_id,
                           itemloc_lotserial, itemloc_qty
                    FROM itemloc
                    WHERE ((itemloc_itemsite_id=_p.itemsite_id)
                      AND  (itemloc_location_id=_p.invcnt_location_id)) LOOP

      _hasDetail = TRUE;

--  Create the itemlocdist flushing records
      INSERT INTO itemlocdist
      ( itemlocdist_series, itemlocdist_source_type, itemlocdist_source_id,
        itemlocdist_lotserial, itemlocdist_expiration,
        itemlocdist_itemsite_id, itemlocdist_invhist_id, itemlocdist_flush )
      VALUES
      ( _itemlocSeries, ''I'', _itemloc.itemloc_id,
        '''', endOfTime(),
        _p.itemsite_id, _invhistid, TRUE );

    END LOOP;

--  Clear the running detail Qty
    _runningQty := 0;

--  Adjust the detail to the cntslip indicated value
    FOR _cntslip IN SELECT cntslip_location_id, cntslip_lotserial,
                           cntslip_lotserial_expiration,
                           SUM(cntslip_qty) AS qty
                    FROM cntslip
                    WHERE (cntslip_cnttag_id=pInvcntid)
                    GROUP BY cntslip_location_id, cntslip_lotserial, cntslip_lotserial_expiration LOOP

--  Track the running Qty
      _runningQty := (_runningQty + _cntslip.qty);
      _hasDetail = TRUE;

--  Create the itemlocdist populating record
      INSERT INTO itemlocdist
      ( itemlocdist_series, itemlocdist_source_type, itemlocdist_source_id,
        itemlocdist_itemsite_id,
        itemlocdist_lotserial, itemlocdist_expiration,
        itemlocdist_qty, itemlocdist_invhist_id )
      VALUES
      ( _itemlocSeries, ''L'', _cntslip.cntslip_location_id,
        _p.itemsite_id,
        _cntslip.cntslip_lotserial, COALESCE(_cntslip.cntslip_lotserial_expiration, endOfTime()),
        _cntslip.qty, _invhistid );

    END LOOP;

    IF (_runningQty > _p.invcnt_qoh_after) THEN
--  The total Count Slip Qty is greater than the Count Tag Qty,
--  Don''t post the Count.
      _errorCode = -1;

    ELSIF ( (_runningQty < _p.invcnt_qoh_after) AND
            (_p.itemsite_controlmethod IN (''L'', ''S'')) ) THEN
--  The total Count Slip Qty is less than the Count Tag Qty,
--  and the Item Site is Lot/Serial controlled.
--  Don''t post the Count.
      _errorCode = -2;

    ELSIF (_runningQty < _p.invcnt_qoh_after) THEN
      IF ( (NOT _p.itemsite_loccntrl) OR
           (_p.itemsite_location_id = -1) ) THEN
--  The total Count Slip Qty is less than the Count Tag Qty,
--  and there isn''t a default location to post into.
--  Don''t post the Count.
        _errorCode = -3;

      ELSIF ( SELECT (metric_value=''f'')
              FROM metric
              WHERE (metric_name=''PostCountTagToDefault'') ) THEN
--  The total Count Slip Qty is less than the Count Tag Qty,
--  and we don''t post Count Tags to default Locations
--  Don''t post the Count.
        _errorCode = -4;

      ELSE
--  Distribute the remaining qty into the default location.
        INSERT INTO itemlocdist
        ( itemlocdist_series, itemlocdist_source_type, itemlocdist_source_id,
          itemlocdist_itemsite_id,
          itemlocdist_lotserial, itemlocdist_expiration,
          itemlocdist_qty, itemlocdist_invhist_id )
        SELECT _itemlocSeries, ''L'', _p.itemsite_location_id,
               _p.itemsite_id,
               '''', endOfTime(),
               (_p.invcnt_qoh_after - _runningQty), _invhistid;

        _hasDetail = TRUE;
        _errorCode = 0;
      END IF;
    ELSE
--  The Count Slip Qty. must equal the Count Tag Qty.
      _errorCode = 0;
    END IF;

--  If we shouldn''t post the count then delete the itemlocdist records,
--  and return with the error.
    IF (_errorCode <> 0) THEN
      DELETE FROM itemlocdist
      WHERE (itemlocdist_series=_itemlocSeries);
  
      RETURN _errorCode;
    END IF;

  END IF;

--  Mod. the Count Tag.
  UPDATE invcnt
  SET invcnt_qoh_before=_origLocQty,
      invcnt_postdate=_postDate,
      invcnt_posted=TRUE,
      invcnt_invhist_id=_invhistid,
      invcnt_post_usr_id=currentUserId()
  WHERE (invcnt_id=pInvcntid);

--  Create the CC transaction
  INSERT INTO invhist
   ( invhist_id, invhist_itemsite_id,
     invhist_transdate, invhist_transtype, invhist_invqty,
     invhist_qoh_before, invhist_qoh_after,
     invhist_docnumber, invhist_comments,
     invhist_invuom, invhist_unitcost, invhist_hasdetail )
  SELECT _invhistid, itemsite_id,
         _postDate, ''CC'', (invcnt_qoh_after - invcnt_qoh_before),
         invcnt_qoh_before, invcnt_qoh_after,
         invcnt_tagnumber, invcnt_comments,
         uom_name, stdCost(item_id), _hasDetail
  FROM itemsite, invcnt, item, uom
  WHERE ( (invcnt_itemsite_id=itemsite_id)
   AND (itemsite_item_id=item_id)
   AND (item_inv_uom_id=uom_id)
   AND (itemsite_controlmethod <> ''N'')
   AND (invcnt_id=pInvcntid) );

--  Update the QOH
  UPDATE itemsite
  SET itemsite_qtyonhand= itemsite_qtyonhand + (_p.invcnt_qoh_after - _origLocQty),
      itemsite_nnqoh = 0,
      itemsite_datelastcount=_postDate
  WHERE (itemsite_id=_p.itemsite_id);
 
--  Post the detail, if any
  IF (_hasDetail) THEN
    PERFORM distributeItemlocSeries(_itemlocSeries);
  END IF;

--  Thaw the itemsite if it''s frozen
  IF (pThaw) THEN
    PERFORM thawItemSite(invcnt_itemsite_id) 
    FROM invcnt
    WHERE (invcnt_id=pInvcntid);
  END IF;

--  Distribute to G/L
  PERFORM insertGLTransaction( ''I/M'', ''CT'', _p.invcnt_tagnumber, (''Post Count Tag #'' || _p.invcnt_tagnumber || '' for Item '' || _p.item_number),
                               costcat_adjustment_accnt_id, costcat_asset_accnt_id, _invhistid,
                               ( (_p.invcnt_qoh_after - _origLocQty) * _p.cost), CURRENT_DATE )
  FROM invcnt, itemsite, costcat
  WHERE ( (invcnt_itemsite_id=itemsite_id)
   AND (itemsite_costcat_id=costcat_id)
   AND (invcnt_id=pInvcntid) );

  RETURN 0;
END;
' LANGUAGE 'plpgsql';
