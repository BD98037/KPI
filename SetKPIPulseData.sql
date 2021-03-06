USE [ProdReports]
GO
/****** Object:  StoredProcedure [dbo].[SetKPIPulseData]    Script Date: 04/30/2015 14:26:10 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROC [dbo].[SetKPIPulseData] 
@CurrentQuarterBegin DateTime = '4/1/2015',
@AsofBookingDate DateTime = NULL,
@QuarterSwitch int = 1

AS
/*
[dbo].[SetKPIPulseData]
@AsofBookingDate ='3/30/2015'
*/

Declare @SQL Varchar(4000),@YTD DateTime,@AsOfBookingDateKey Int, @AsOflyBookingDateKey Int,@YTDKey Int, @cyQRTDateBegin DateTime, 
			@cyQRTDateEnd DateTime,
			@cyQRTDateBeginKey Int,@cyQRTDateEndKey Int,@lyQRTDateBegin DateTime, @lyQRTDateBeginKey Int,@lyQRTDateEnd DateTime, 
			@lyQRTDateEndKey Int,@ExistingBookingDate DateTime

SELECT TOP 1 @ExistingBookingDate = AsOfBookingDate FROM KPIPulseData
			
IF(@AsofBookingDate IS NULL)
	SELECT  @AsofBookingDate = "[Measures].[ValidDate]"
	FROM
	(
	SELECT * 
	FROM OPENQUERY(EDWCUBES_LODGINGBOOKING,'
	WITH 

	MEMBER [Measures].[ValidDate] AS CDATE([Booking Date].[Date].CURRENTMEMBER.MEMBER_CAPTION)

	SELECT {[Measures].[ValidDate]} ON COLUMNS, 

	{Tail(NonEmptyCrossJoin([Booking Date].[Date].AllMembers), 1).Item(0).Item(0)} ON ROWS

	FROM [LodgingBooking]')
	) d
--SELECT @ExistingBookingDate ExistingBookingDate ,@AsofBookingDate AsofBookingDate

IF(@AsofBookingDate>@ExistingBookingDate)
	BEGIN
		SELECT TOP 1
		@YTD = '1/1/'+CONVERT(Varchar(4),Year(@AsofBookingDate)),
		@cyQRTDateBegin = dbo.GetQtrBegin(@AsOfBookingDate),
		@cyQRTDateEnd = DateAdd(d,-1,DATEADD(QUARTER,1,dbo.GetQtrBegin(@AsOfBookingDate))),
		@lyQRTDateEnd = DateAdd(d,-1,DateAdd(m,-12,DateAdd(QUARTER,1,dbo.GetQtrBegin(@AsofBookingDate)))) ,
		@lyQRTDateBegin =DateAdd(m,-12,dbo.GetQtrBegin(@AsOfBookingDate)),
		@AsOfBookingDateKey = DATE_KEY
		FROM Mirror.DB2_DM.DATE_DIM WHERE ACTUAL_DATE =@AsofBookingDate
	   
	--SELECT @cyQRTDateBegin cyQRTDateBegin,@CurrentQuarterBegin CurrentQuarterBegin
 
	IF(@cyQRTDateBegin=@CurrentQuarterBegin)
		BEGIN
			SELECT @cyQRTDateBeginKey = DATE_KEY FROM Mirror.DB2_DM.DATE_DIM WHERE ACTUAL_DATE = @CyQRTDateBegin
			SELECT @cyQRTDateEndKey = DATE_KEY FROM Mirror.DB2_DM.DATE_DIM WHERE ACTUAL_DATE = @cyQRTDateEnd
			SELECT @lyQRTDateBeginKey = DATE_KEY FROM Mirror.DB2_DM.DATE_DIM WHERE ACTUAL_DATE = @lyQRTDateBegin
			SELECT @lyQRTDateEndKey = DATE_KEY FROM Mirror.DB2_DM.DATE_DIM WHERE ACTUAL_DATE = @lyQRTDateEnd
			SELECT @AsOflyBookingDateKey = DATE_KEY FROM Mirror.DB2_DM.DATE_DIM WHERE ACTUAL_DATE = DATEADD(d,-365,@AsofBookingDate)


			/* Need to use this query to ensure the targets won't change*/
			
			DECLARE @HIERARCHYDATE DATETIME,@QUARTER_START_SNAPSHOT INT =1
			SET @HIERARCHYDATE = case 
				 when @QUARTER_START_SNAPSHOT = 1 then (select MIN(Update_Date) from SSAtools.dbo.VIPHierarchy_Snapshot where snapshotquarterbegindate = @CurrentQuarterBegin)
				 else (select MAX(Update_Date) from SSAtools.dbo.VIPHierarchy_Snapshot where snapshotquarterbegindate = @CurrentQuarterBegin) end
			     
			 SELECT vip.* INTO #StaticHierarchy 
			 FROM SSAtools.dbo.VIPHierarchy_Snapshot vip   
			WHERE    vip.Update_Date = @HIERARCHYDATE 
				 AND vip.SnapshotQuarterBeginDate = @CurrentQuarterBegin
				 AND ISNULL(SuperRegionID,0) >0 AND ExpediaID <>10023570

			SELECT * INTO #vSIP_Hierarchy FROM [vSIP_Hierarchy ]

			CREATE CLUSTERED INDEX idx_#HotelKey ON #vSIP_Hierarchy (HotelKey)

			--Get Plan & PK Savings Actuals QTD
			CREATE TABLE #CyProd
			(
			MARKETID INT,
			MAAID INT,
			MMAID INT,
			NRN FLOAT,
			NP FLOAT,
			RMD FLOAT,
			HFS_NUM INT,
			HFS_DENOM INT
			)
			
			CREATE TABLE #LyProd
			(
			MARKETID INT,
			MAAID INT,
			MMAID INT,
			NRN FLOAT,
			NP FLOAT,
			RMD FLOAT
			)

			PRINT('Starting PK Savings...') 
			PRINT(GETDATE())

			SET @SQL = '
			SELECT *
			FROM OPENQUERY(EDW,
			''
			SELECT
			 COALESCE(PROPERTY_MKT_ID,0) AS MarketID
			,CASE WHEN MKT_ASSOCIATE_AREA_ID < 0 THEN 0 ELSE COALESCE(MKT_ASSOCIATE_AREA_ID,0) END MAAID
			,CASE WHEN MKT_MGMT_TERRITORY_ID < 0 THEN 0 ELSE COALESCE(MKT_MGMT_TERRITORY_ID,0) END  MMAID
			,SUM(RM_NIGHT_CNT) Actual_NRN
			,SUM(GROSS_BKG_AMT_USD) Actual_NP
			,SUM(MARGN_AMT_USD + FRNT_END_CMSN_AMT_USD) Actual_RMD
			,SUM(CASE WHEN STNDAL_LODG_REF_IND = ''''Standalone Lodging Reference Price''''  AND TRANS_TYP_KEY = 101
							AND PKG_IND = ''''Part Of Package'''' AND PKG_TYP_NAME = ''''Standard'''' 
							AND MGMT_UNIT_LVL_5_NAME IN (''''Expedia All'''',''''Expedia Travelocity'''',''''Air Asia Expedia Joint Venture'''')   
						THEN STNDAL_CMPRBL_REF_COST_USD - TOTL_COST_AMT_USD ELSE 0 END) HFS_NUM
			,SUM(CASE WHEN STNDAL_LODG_REF_IND = ''''Standalone Lodging Reference Price''''  AND TRANS_TYP_KEY = 101
							AND PKG_IND = ''''Part Of Package'''' AND PKG_TYP_NAME = ''''Standard'''' 
							AND MGMT_UNIT_LVL_5_NAME IN (''''Expedia All'''',''''Expedia Travelocity'''',''''Air Asia Expedia Joint Venture'''') 
						THEN STNDAL_CMPRBL_REF_COST_USD ELSE 0 END) HFS_DENOM
			  
			FROM DM.V_LODG_PROPERTY_DIM h
			  JOIN DM.V_LODG_RM_TRANS_FACT f ON f.LODG_PROPERTY_KEY=h.LODG_PROPERTY_KEY
			  --LEFT JOIN PSGSCRATCH.SIP_Hierarchy  sip ON sip.HotelKey =h.LODG_PROPERTY_KEY
			  JOIN DM.BKG_IND_DIM ex ON ex.BKG_IND_KEY = F.BKG_IND_KEY
			  JOIN DM.V_PRODUCT_LN_DIM PL ON PL.PRODUCT_LN_KEY=F.PRODUCT_LN_KEY
			  LEFT JOIN DM.MGMT_UNIT_DIM MU ON F.MGMT_UNIT_KEY = MU.MGMT_UNIT_KEY
			  LEFT JOIN DM.V_STNDAL_LODG_REF_IND_DIM s ON f.STNDAL_LODG_REF_IND_KEY= s.STNDAL_LODG_REF_IND_KEY
			  WHERE f.TRANS_DATE_KEY BETWEEN '+ CONVERT(VARCHAR(10),@cyQRTDateBeginKey) +' AND '+ CONVERT(VARCHAR(10),@AsOfBookingDateKey) +'
					 AND ex.BKG_SYS_OF_REC_ID NOT IN (-9993,-9988) ---exclude Tourico and HotelBeds
					 AND BUSINESS_MODEL_SUBTYP_NAME <>''''Agency'''' AND PRODUCT_LN_NAME =''''Lodging''''
			GROUP BY
			  COALESCE(PROPERTY_MKT_ID,0)
			,CASE WHEN MKT_ASSOCIATE_AREA_ID < 0 THEN 0 ELSE COALESCE(MKT_ASSOCIATE_AREA_ID,0) END
			,CASE WHEN MKT_MGMT_TERRITORY_ID < 0 THEN 0 ELSE COALESCE(MKT_MGMT_TERRITORY_ID,0) END 
			''
			) '
			
			INSERT INTO #CyProd
			EXEC(@SQL)
			CREATE CLUSTERED INDEX idx_#STIDs ON #CyProd(MarketID,MMAID,MAAID)
			
			PRINT('Starting Ly actuals...') 
			PRINT(GETDATE())

			SET @SQL = '
			SELECT *
			FROM OPENQUERY(EDW,
			''
			SELECT
			 COALESCE(PROPERTY_MKT_ID,0) AS MarketID
			,CASE WHEN MKT_ASSOCIATE_AREA_ID < 0 THEN 0 ELSE COALESCE(MKT_ASSOCIATE_AREA_ID,0) END MAAID
			,CASE WHEN MKT_MGMT_TERRITORY_ID < 0 THEN 0 ELSE COALESCE(MKT_MGMT_TERRITORY_ID,0) END  MMAID
			,SUM(RM_NIGHT_CNT) Actual_NRN
			,SUM(GROSS_BKG_AMT_USD) Actual_NP
			,SUM(MARGN_AMT_USD + FRNT_END_CMSN_AMT_USD) Actual_RMD
			
			FROM DM.V_LODG_PROPERTY_DIM h
			  JOIN DM.V_LODG_RM_TRANS_FACT f ON f.LODG_PROPERTY_KEY=h.LODG_PROPERTY_KEY
			  JOIN DM.BKG_IND_DIM ex ON ex.BKG_IND_KEY = F.BKG_IND_KEY
			  JOIN DM.V_PRODUCT_LN_DIM PL ON PL.PRODUCT_LN_KEY=F.PRODUCT_LN_KEY
			  LEFT JOIN DM.MGMT_UNIT_DIM MU ON F.MGMT_UNIT_KEY = MU.MGMT_UNIT_KEY
			  WHERE f.TRANS_DATE_KEY BETWEEN '+ CONVERT(VARCHAR(10),@lyQRTDateBeginKey) +' AND '+ CONVERT(VARCHAR(10),@AsOflyBookingDateKey) +'
					 AND ex.BKG_SYS_OF_REC_ID NOT IN (-9993,-9988) ---exclude Tourico and HotelBeds
					 AND BUSINESS_MODEL_SUBTYP_NAME <>''''Agency'''' AND PRODUCT_LN_NAME =''''Lodging''''
			GROUP BY
			 COALESCE(PROPERTY_MKT_ID,0)
			,CASE WHEN MKT_ASSOCIATE_AREA_ID < 0 THEN 0 ELSE COALESCE(MKT_ASSOCIATE_AREA_ID,0) END
			,CASE WHEN MKT_MGMT_TERRITORY_ID < 0 THEN 0 ELSE COALESCE(MKT_MGMT_TERRITORY_ID,0) END 
			''
			) '

			INSERT INTO #LyProd
			EXEC(@SQL)
			CREATE CLUSTERED INDEX idx_#STIDs ON #LyProd(MarketID,MMAID,MAAID)

		
			TRUNCATE TABLE dbo.KPI_Targets_HFSByHotel 
			INSERT INTO dbo.KPI_Targets_HFSByHotel 
			(
			HotelKey,
			NUM_HFS,
			DENOM_HFS,
			MARKETID
			)
			SELECT 
			hotel_key,
			HOTEL_HFS_TAR_N,
			HOTEL_HFS_TAR_D,
			market_id
			FROM ssa.dbo.AP_KPI2015_HFS2015TAR_HOTEL
			WHERE date_update = @CurrentQuarterBegin


			SELECT
			ISNULL(vip.MarketID,0) MarketID,
			ISNULL(MAAID,0) MAAID,
			ISNULL(MMAID,0) MMAID,
			SUM(DENOM_HFS) DENOM_HFS,
			SUM(NUM_HFS) NUM_HFS
			INTO #tHFS
			FROM dbo.KPI_Targets_HFSByHotel t
			JOIN #StaticHierarchy vip ON t.HotelKey = vip.HotelKey

			GROUP BY
			ISNULL(vip.MarketID,0),
			ISNULL(MAAID,0),
			ISNULL(MMAID,0)

			CREATE CLUSTERED INDEX idx_#STIDs ON #tHFS(MarketID,MMAID,MAAID)

			PRINT('Starting Plan Data...')
			PRINT(GETDATE())
			--Get Plan
			SELECT
			ISNULL(MarketID,0) MarketID,
			ISNULL(MAAID,0) MAAID,
			ISNULL(MMAID,0) MMAID,
			SUM(Coalesce(TargetRMD,0)) As FullQPlanRMD,
			SUM(Coalesce(TargetNRN,0)) As FullQPlanNRN,
			SUM(CASE WHEN DATE_KEY <= @AsOfBookingDateKey THEN Coalesce(TargetRMD,0) ELSE 0 END) As QTDPlanRMD,
			SUM(CASE WHEN DATE_KEY <= @AsOfBookingDateKey THEN Coalesce(TargetNRN,0) ELSE 0 END) As QTDPlanNRN
			INTO #Plan
			FROM PlanDb.dbo.GMMPlanData p
			JOIN #vSIP_Hierarchy  sip ON p.LODG_PROPERTY_KEY = sip.HotelKey
			WHERE p.DATE_KEY BETWEEN @cyQRTDateBeginKey AND @cyQRTDateEndKey
			GROUP BY 
			ISNULL(MarketID,0),
			ISNULL(MAAID,0),
			ISNULL(MMAID,0)

			CREATE CLUSTERED INDEX idx_#STIDs ON #Plan(MarketID,MMAID,MAAID)

			PRINT('Starting Acq...')
			PRINT(GETDATE())
			--Actuals
			SELECT 
			--sip.MarketID,
			--sip.MAAID,
			sip.MMAID,
			SUM(RMD_QTD_Total) aAcq
			INTO #AcqActuals
			FROM Acquisition.dbo. AcqReport_ProdDetails_R4QHotel_Final a
			JOIN vSIP_Hierarchy  sip ON a.HotelKey = sip.HotelKey
			--WHERE AcqYear = 2015
			GROUP BY 
			--sip.MarketID,
			--sip.MAAID,
			sip.MMAID

			CREATE CLUSTERED INDEX idx_#STIDs ON #AcqActuals(MMAID)

			--Targets
			SELECT s.MMAID,
			SUM(RMD_Target) tAcq
			INTO #AcqTargets
			FROM SSA.dbo.AP_KPI2015_ACQ_TAR t
			JOIN (SELECT DISTINCT MMAID FROM vSIP_Hierarchy ) s
			ON t.MMA_ID = s.MMAID
			WHERE t.date_update =@CurrentQuarterBegin
			GROUP BY s.MMAID
			
			CREATE CLUSTERED INDEX idx_#STIDs ON #AcqTargets(MMAID)
			
			--Pacing
			SELECT DISTINCT
			MMAID,
			PaceFactor_R4Q pAcq
			INTO #AcqPace
			FROM SSA.dbo.AE_2015Acq_Pacing_Quarterly
			WHERE DATE = @AsofBookingDate
			
			CREATE CLUSTERED INDEX idx_#STIDs ON #AcqPace(MMAID)
			
			TRUNCATE TABLE dbo.KPIAcq
			INSERT INTO dbo.KPIAcq
			SELECT 
			m.MMAID,
			ISNULL(aAcq.aAcq,0) aAcq,
			ISNULL(tAcq.tAcq,0) tAcq,
			ISNULL(pAcq.pAcq,0) pAcq
			FROM (SELECT DISTINCT MMAID FROM #vSIP_Hierarchy )  m  
			LEFT JOIN #AcqActuals aAcq ON  m.MMAID = aAcq.MMAID
			LEFT JOIN #AcqTargets tAcq ON m.MMAID = tAcq.MMAID
			LEFT JOIN #AcqPace pAcq ON m.MMAID = pAcq.MMAID

			PRINT('Starting BML...')
			PRINT(GETDATE())
			--Get BML Scores
			TRUNCATE TABLE dbo.KPI_BMLTargets
			INSERT INTO dbo.KPI_BMLTargets
			SELECT
			Hotel_Key HotelKey,
			Null,
			RateN,
			AvailN,
			RateD,
			AvailD
			FROM SSA.dbo.AP_KPI2015_BML_TAR_CI
			WHERE date_update = @CurrentQuarterBegin
	
			SELECT
			ISNULL(MarketID,0) MarketID,
			ISNULL(MAAID,0) MAAID,
			ISNULL(MMAID,0) MMAID,
			SUM(bml.availdenom) AvailD,
			SUM(bml.availnumer) AvailN,
			SUM(bml.ratedenom) RateD,
			SUM(bml.ratenumer) RateN
			INTO #tBML
			FROM dbo.KPI_BMLTargets bml
			JOIN #StaticHierarchy sip ON bml.HotelKey = sip.HotelKey
			GROUP BY
			ISNULL(MarketID,0),
			ISNULL(MAAID,0),
			ISNULL(MMAID,0)

			CREATE CLUSTERED INDEX idx_#STIDs ON #tBML(MarketID,MMAID,MAAID)

			--Get BML Actuals
			Declare @BMLMDX Varchar(4000)

			CREATE TABLE #BML(HotelKey Varchar(10),SuperRegionName VarChar(10),AvailD VarChar(50),RateD VarChar(50),AvailN VarChar(50), RateN VarChar(50))

			PRINT('Starting BML AMER...')
			PRINT(GETDATE())
			-- AMER
			SET @BMLMDX ='
			SELECT * FROM OPENQUERY(EDWCubes_LODGBML,''
			WITH 
			MEMBER Measures.AvailD AS [Measures].[Avail D Score]
			MEMBER Measures.RateD AS [Measures].[Rate D Score]
			MEMBER Measures.AvailN AS [Measures].[Avail Lose N Score]
			MEMBER Measures.RateN AS [Measures].[Rate Lose N Score]

			SELECT
			Non Empty
			{
			Measures.AvailD,
			Measures.RateD,
			Measures.AvailN,
			Measures.RateN
			} on columns,
			Non Empty
			(
			[Hotel].[Hotel Key].[Hotel Key],
			[Hotel].[Super Region Name].&[AMER]
			) on rows

			FROM ( 
					SELECT (
							EXCEPT(
								{([Comp Site].[Comp Site Name].[All].Children)},
								{(
									{[Comp Site].[Comp Site Name].&[Booking.com (BOOKING_FAM)]}
								)}
							)
					) ON COLUMNS

			FROM [BML - Lodging])

			WHERE 

			({
			[Shop Type].[Shop Type By Category].[Shop Type Category].&[1], --default
			[Shop Type].[Shop Type By Category].[Shop Type Category].&[4],-- sameday
			[Shop Type].[Shop Type By Category].[Shop Type Category].&[8]-- mobile
			},
			[Ref Site].[Ref Site Group].[Ref Site Group Name].&[Expedia],
			[Comp Site].[Is Expedia Site Group].&[No],
			([Shopped Date].[Shopped Date].[Date].['+Convert(varchar(10),@cyQRTDateBegin,120)+']:[Shopped Date].[Shopped Date].[Date].['+Convert(varchar(10),@AsOfBookingDate,120)+'])
			)
			'')'
			INSERT INTO #BML
			EXEC(@BMLMDX) 

			PRINT('Starting BML EMEA...')
			PRINT(GETDATE())
			-- EMEA
			SET @BMLMDX ='
			SELECT * FROM OPENQUERY(EDWCubes_LODGBML,''
			WITH 
			MEMBER Measures.AvailD AS [Measures].[Avail D Score]
			MEMBER Measures.RateD AS [Measures].[Rate D Score]
			MEMBER Measures.AvailN AS [Measures].[Avail Lose N Score]
			MEMBER Measures.RateN AS [Measures].[Rate Lose N Score]

			SELECT
			Non Empty
			{
			Measures.AvailD,
			Measures.RateD,
			Measures.AvailN,
			Measures.RateN
			} on columns,
			Non Empty
			(
			[Hotel].[Hotel Key].[Hotel Key],
			[Hotel].[Super Region Name].&[EMEA]
			) on rows

			FROM ( 
					SELECT (
							EXCEPT(
								{([Comp Site].[Comp Site Name].[All].Children)},
								{(
									{[Comp Site].[Comp Site Name].&[Booking.com (BOOKING_FAM)]}
								)}
							)
					) ON COLUMNS

			FROM [BML - Lodging])

			WHERE 

			({
			[Shop Type].[Shop Type By Category].[Shop Type Category].&[1], --default
			[Shop Type].[Shop Type By Category].[Shop Type Category].&[4],-- sameday
			[Shop Type].[Shop Type By Category].[Shop Type Category].&[8]-- mobile
			},
			[Ref Site].[Ref Site Group].[Ref Site Group Name].&[Expedia],
			[Comp Site].[Is Expedia Site Group].&[No],
			([Shopped Date].[Shopped Date].[Date].['+Convert(varchar(10),@cyQRTDateBegin,120)+']:[Shopped Date].[Shopped Date].[Date].['+Convert(varchar(10),@AsOfBookingDate,120)+'])
			)
			'')'
			INSERT INTO #BML
			EXEC(@BMLMDX) 

			PRINT('Starting BML APAC...')
			PRINT(GETDATE())
			-- APAC
			SET @BMLMDX ='
			SELECT * FROM OPENQUERY(EDWCubes_LODGBML,''
			WITH 
			MEMBER Measures.AvailD AS [Measures].[Avail D Score]
			MEMBER Measures.RateD AS [Measures].[Rate D Score]
			MEMBER Measures.AvailN AS [Measures].[Avail Lose N Score]
			MEMBER Measures.RateN AS [Measures].[Rate Lose N Score]

			SELECT
			Non Empty
			{
			Measures.AvailD,
			Measures.RateD,
			Measures.AvailN,
			Measures.RateN
			} on columns,
			Non Empty
			(
			[Hotel].[Hotel Key].[Hotel Key],
			[Hotel].[Super Region Name].&[APAC]
			) on rows

			FROM ( 
					SELECT (
							EXCEPT(
								{([Comp Site].[Comp Site Name].[All].Children)},
								{(
									{[Comp Site].[Comp Site Name].&[Booking.com (BOOKING_FAM)]}
								)}
							)
					) ON COLUMNS

			FROM [BML - Lodging])

			WHERE 

			({
			[Shop Type].[Shop Type By Category].[Shop Type Category].&[1], --default
			[Shop Type].[Shop Type By Category].[Shop Type Category].&[4],-- sameday
			[Shop Type].[Shop Type By Category].[Shop Type Category].&[8]-- mobile
			},
			[Ref Site].[Ref Site Group].[Ref Site Group Name].&[Expedia],
			[Comp Site].[Is Expedia Site Group].&[No],
			([Shopped Date].[Shopped Date].[Date].['+Convert(varchar(10),@cyQRTDateBegin,120)+']:[Shopped Date].[Shopped Date].[Date].['+Convert(varchar(10),@AsOfBookingDate,120)+'])
			)
			'')'
			INSERT INTO #BML
			EXEC(@BMLMDX) 

			PRINT('Starting BML LATAM...')
			PRINT(GETDATE())
			-- LATAM
			SET @BMLMDX ='
			SELECT * FROM OPENQUERY(EDWCubes_LODGBML,''
			WITH 
			MEMBER Measures.AvailD AS [Measures].[Avail D Score]
			MEMBER Measures.RateD AS [Measures].[Rate D Score]
			MEMBER Measures.AvailN AS [Measures].[Avail Lose N Score]
			MEMBER Measures.RateN AS [Measures].[Rate Lose N Score]

			SELECT
			Non Empty
			{
			Measures.AvailD,
			Measures.RateD,
			Measures.AvailN,
			Measures.RateN
			} on columns,
			Non Empty
			(
			[Hotel].[Hotel Key].[Hotel Key],
			[Hotel].[Super Region Name].&[LATAM]
			) on rows

			FROM ( 
					SELECT (
							EXCEPT(
								{([Comp Site].[Comp Site Name].[All].Children)},
								{(
									{[Comp Site].[Comp Site Name].&[Booking.com (BOOKING_FAM)]}
								)}
							)
					) ON COLUMNS

			FROM [BML - Lodging])

			WHERE 

			({
			[Shop Type].[Shop Type By Category].[Shop Type Category].&[1], --default
			[Shop Type].[Shop Type By Category].[Shop Type Category].&[4],-- sameday
			[Shop Type].[Shop Type By Category].[Shop Type Category].&[8]-- mobile
			},
			[Ref Site].[Ref Site Group].[Ref Site Group Name].&[Expedia],
			[Comp Site].[Is Expedia Site Group].&[No],
			([Shopped Date].[Shopped Date].[Date].['+Convert(varchar(10),@cyQRTDateBegin,120)+']:[Shopped Date].[Shopped Date].[Date].['+Convert(varchar(10),@AsOfBookingDate,120)+'])
			)
			'')'
			INSERT INTO #BML
			EXEC(@BMLMDX) 

			CREATE CLUSTERED INDEX idx_#HotelKey ON #BML(HotelKey)

			SELECT 
			ISNULL(MarketID,0) MarketID,
			ISNULL(MAAID,0) MAAID,
			ISNULL(MMAID,0) MMAID,
			SUM(CONVERT(FLOAT,AvailD)) AvailD,
			SUM(CONVERT(FLOAT,AvailN)) AvailN,
			SUM(CONVERT(FLOAT,RateD)) RateD,
			SUM(CONVERT(FLOAT,RateN)) RateN
			INTO #aBML
			FROM #BML bml
			JOIN #StaticHierarchy  sip ON bml.HotelKey = sip.HotelKey
			GROUP BY 
			ISNULL(MarketID,0),
			ISNULL(MAAID,0),
			ISNULL(MMAID,0)

			CREATE CLUSTERED INDEX idx_#STIDs ON #aBML(MarketID,MMAID,MAAID)

			 PRINT('Combine all data...')  
			 PRINT(GETDATE())
			 
			TRUNCATE TABLE [dbo].[KPIPulseData]
			INSERT INTO [dbo].[KPIPulseData]
			SELECT DISTINCT
			ISNULL(m.MarketID,0) MarketID,
			ISNULL(m.MAAID,0) MAAID,
			ISNULL(m.MMAID,0) MMAID,
			@AsOfBookingDate AS AsOfBookingDate,
			ISNULL(CASE WHEN ISNULL(thfs.DENOM_HFS,0) = 0 THEN 0 ELSE 
					CASE WHEN ISNULL(thfs.NUM_HFS,0)/ISNULL(thfs.DENOM_HFS,0) = 0 THEN 0
							ELSE cyprod.HFS_NUM END END,0) AS aNUM_HFS,
			ISNULL(CASE WHEN ISNULL(thfs.DENOM_HFS,0) = 0 THEN 0 ELSE 
					CASE WHEN ISNULL(thfs.NUM_HFS,0)/ISNULL(thfs.DENOM_HFS,0) = 0 THEN 0
							ELSE cyprod.HFS_DENOM END END,0) aDENOM_HFS,
			ISNULL(thfs.NUM_HFS,0) tNUM_HFS,
			ISNULL(thfs.DENOM_HFS,0) tDENOM_HFS,
			ISNULL(cyprod.NRN,0) QTDCyActualNRN,
			ISNULL(cyprod.RMD,0) QTDCyActualRMD,
			ISNULL(lyap.NRN,0) QTDLyActualNRN,
			ISNULL(lyap.RMD,0) QTDLyActualRMD,
			ISNULL(tp.QTDPlanNRN,0) QTDPlanNRN,
			ISNULL(tp.QTDPlanRMD,0) QTDPlanRMD,
			ISNULL(tp.FullQPlanNRN,0) FullQPlanNRN,
			ISNULL(tp.FullQPlanRMD,0) FullQPlanRMD,
			0 tAcq,
			0 aAcq,
			ISNULL(abs(rs.AvailD),0) AS tAvailD,
			ISNULL(abs(rs.AvailN),0) AS tAvailN,
			ISNULL(abs(rs.RateD),0) AS tRateD,
			ISNULL(abs(rs.RateN),0) AS tRateN,
			ISNULL(abs(abml.AvailD),0) AS aAvailD,
			ISNULL(abs(abml.AvailN),0) AS aAvailN,
			ISNULL(abs(abml.RateD),0) AS aRateD,
			ISNULL(abs(abml.RateN),0) AS aRateN,
			0 pAcq

			--INTO select * from [dbo].[KPIPulseData]  where mmaid =0

			FROM (SELECT DISTINCT MarketID,MAAID,MMAID FROM #vSIP_Hierarchy )  m 
			LEFT JOIN #CyProd cyprod ON m.MarketID = cyprod.MarketID AND m.MAAID = cyprod.MAAID AND m.MMAID = cyprod.MMAID
			LEFT JOIN #tHFS thfs ON m.MarketID = thfs.MarketID AND m.MAAID = thfs.MAAID AND m.MMAID = thfs.MMAID
			LEFT JOIN #Plan tp ON m.MarketID = tp.MarketID AND m.MAAID = tp.MAAID AND m.MMAID = tp.MMAID
			LEFT JOIN #LyProd lyap ON m.MarketID = lyap.MarketID AND m.MAAID = lyap.MAAID AND m.MMAID = lyap.MMAID
			LEFT JOIN #tBML rs ON m.MarketID = rs.MarketID AND m.MAAID = rs.MAAID AND m.MMAID = rs.MMAID
			LEFT JOIN #aBML abml ON m.MarketID = abml.MarketID and m.MAAID = abml.MAAID AND m.MMAID = abml.MMAID
			
			
			/************************************
			For the markets with MMA/MAA not exist
			*************************************/
			
			--current year
			INSERT INTO [dbo].[KPIPulseData]
			SELECT DISTINCT
			cyprod.MarketID,
			ISNULL(m.MAAID,0) MAAID,
			ISNULL(m.MMAID,0) MMAID,
			@AsofBookingDate,
			ISNULL(HFS_NUM,0) aNUM_HFS,
			ISNULL(HFS_DENOM,0) aDENOM_HFS,
			0 tNUM_HFS,
			0 tDENOM_HFS,
			ISNULL(cyprod.NRN,0) QTDCyActualNRN,
			ISNULL(cyprod.RMD,0) QTDCyActualRMD,
			0 QTDLyActualNRN,
			0 QTDLyActualRMD,
			0 QTDPlanNRN,
			0 QTDPlanRMD,
			0 FullQPlanNRN,
			0 FullQPlanRMD,
			0 tAcq,
			0 aAcq,
			0 tAvailD,
			0 tAvailN,
			0 tRateD,
			0 tRateN,
			0 aAvailD,
			0 aAvailN,
			0 aRateD,
			0 aRateN,
			0 pAcq
			FROM #CyProd cyprod 
			LEFT JOIN (SELECT DISTINCT MarketID,MAAID,MMAID FROM #vSIP_Hierarchy ) m ON m.MarketID = cyprod.MarketID AND m.MAAID = cyprod.MAAID AND m.MMAID = cyprod.MMAID
			WHERE m.MARKETID IS NULL
			
			--last year
			INSERT INTO [dbo].[KPIPulseData]
			SELECT DISTINCT
			lyprod.MarketID,
			ISNULL(m.MAAID,0) MAAID,
			ISNULL(m.MMAID,0) MMAID,
			@AsofBookingDate,
			0 aNUM_HFS,
			0 aDENOM_HFS,
			0 tNUM_HFS,
			0 tDENOM_HFS,
			0 QTDCyActualNRN,
			0 QTDCyActualRMD,
			ISNULL(lyprod.NRN,0) QTDlyActualNRN,
			ISNULL(lyprod.RMD,0) QTDlyActualRMD,
			0 QTDPlanNRN,
			0 QTDPlanRMD,
			0 FullQPlanNRN,
			0 FullQPlanRMD,
			0 tAcq,
			0 aAcq,
			0 tAvailD,
			0 tAvailN,
			0 tRateD,
			0 tRateN,
			0 aAvailD,
			0 aAvailN,
			0 aRateD,
			0 aRateN,
			0 pAcq
			
			FROM #LyProd lyprod 
			LEFT JOIN (SELECT DISTINCT MarketID,MAAID,MMAID FROM #vSIP_Hierarchy ) m ON m.MarketID = lyprod.MarketID AND m.MAAID = lyprod.MAAID AND m.MMAID = lyprod.MMAID
			WHERE m.MARKETID IS NULL
			
			--Store for Expedient Feed
				TRUNCATE TABLE [dbo].[KPIPulseData_Expedient]
				INSERT INTO [dbo].[KPIPulseData_Expedient]
				SELECT * FROM [dbo].[KPIPulseData]

		END
		
		IF(@QuarterSwitch=1)
			BEGIN
				PRINT('Put new quarter targets into this')
			END

	END	

			--Store for Callidus
				TRUNCATE TABLE dbo.KPIPulseData_Callidus
				INSERT INTO dbo.KPIPulseData_Callidus
				SELECT * FROM dbo.KPIPulseData