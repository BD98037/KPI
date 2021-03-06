USE [ProdReports]
GO
/****** Object:  StoredProcedure [dbo].[SetKPIPulseData_AdHoc]    Script Date: 04/30/2015 14:27:27 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROC [dbo].[SetKPIPulseData_AdHoc] 
 @CurrentQuarterBegin DateTime = '1/1/2015',
@QUARTER_START_SNAPSHOT INT =1
AS
/*
[dbo].[SetKPIPulseData_AdHoc] 
@CurrentQuarterBegin ='1/1/2015'
*/

Declare @SQL Varchar(4000),@YTD DateTime,@AsOfBookingDate DateTime,@AsOfBookingDateKey Int, @AsOflyBookingDateKey Int,@YTDKey Int, @cyQRTDateBegin DateTime, 
			@cyQRTDateEnd DateTime,
			@cyQRTDateBeginKey Int,@cyQRTDateEndKey Int,@lyQRTDateBegin DateTime, @lyQRTDateBeginKey Int,@lyQRTDateEnd DateTime, 
			@lyQRTDateEndKey Int,@ExistingBookingDate DateTime,@HIERARCHYDATE DATETIME
			
SET @HIERARCHYDATE = case 
     when @QUARTER_START_SNAPSHOT = 1 then (select MIN(Update_Date) from SSAtools.dbo.VIPHierarchy_Snapshot where snapshotquarterbegindate = @CurrentQuarterBegin)
     else (select MAX(Update_Date) from SSAtools.dbo.VIPHierarchy_Snapshot where snapshotquarterbegindate = @CurrentQuarterBegin) end
 
SELECT @cyQRTDateBeginKey = DATE_KEY FROM Mirror.DB2_DM.DATE_DIM WHERE ACTUAL_DATE = @CurrentQuarterBegin
SELECT @cyQRTDateEndKey = DATE_KEY FROM Mirror.DB2_DM.DATE_DIM WHERE ACTUAL_DATE = DATEADD(d,-1,DATEADD(QUARTER,1,@CurrentQuarterBegin))
SELECT @lyQRTDateBeginKey = DATE_KEY FROM Mirror.DB2_DM.DATE_DIM WHERE ACTUAL_DATE = DATEADD(m,-12,@CurrentQuarterBegin)
SELECT @lyQRTDateEndKey = DATE_KEY FROM Mirror.DB2_DM.DATE_DIM WHERE ACTUAL_DATE = DATEADD(m,-12,DATEADD(d,-1,DATEADD(QUARTER,1,@CurrentQuarterBegin)))
SET @AsOfBookingDate = DATEADD(d,-1,DATEADD(Quarter,1,@CurrentQuarterBegin))
SELECT @AsOfBookingDateKey = DATE_KEY
		FROM Mirror.DB2_DM.DATE_DIM WHERE ACTUAL_DATE =@AsofBookingDate     
SELECT vip.* 
INTO #vSIP_Hierarchy 
FROM SSAtools.dbo.VIPHierarchy_Q1Deduped vip--SSAtools.dbo.VIPHierarchy_Snapshot vip   
WHERE    vip.Update_Date = @HIERARCHYDATE 
     AND vip.SnapshotQuarterBeginDate = @CurrentQuarterBegin
     AND ISNULL(SuperRegionID,0) >0 AND ExpediaID <>10023570

CREATE CLUSTERED INDEX idx_#HotelKey ON #vSIP_Hierarchy (HotelKey)

SELECT
 ISNULL(vip.MarketID,0) MarketID,   
 ISNULL(vip.MMAID,0) MMAID,
 ISNULL(vip.MAAID,0) MAAID, 
 SUM(ISNULL(p.NRN,0)) NRN,
 SUM(ISNULL(p.TAV,0)) RMD
INTO #CyProd
FROM SSA.dbo.AM_KPI2015_PROD_ACT_HOTEL p
JOIN #vSIP_Hierarchy vip ON p.hotel_key = vip.Hotelkey
WHERE p.date_update = @CurrentQuarterBegin
GROUP BY
 ISNULL(vip.MarketID,0),   
 ISNULL(vip.MMAID,0),
 ISNULL(vip.MAAID,0)
 
CREATE CLUSTERED INDEX idx_#STIDs ON #CyProd(MarketID,MMAID,MAAID)

SELECT
 ISNULL(vip.MarketID,0) MarketID,   
 ISNULL(vip.MMAID,0) MMAID,
 ISNULL(vip.MAAID,0) MAAID, 
SUM(HOTEL_HFS_ACT_D) DENOM_HFS,
SUM(HOTEL_HFS_ACT_N) NUM_HFS
INTO #aHFS
FROM SSA.dbo.AM_KPI2015_HFS_ACT_HOTEL t
JOIN #vSIP_Hierarchy  vip ON t.hotel_key = vip.HotelKey
WHERE t.date_update =@CurrentQuarterBegin
GROUP BY
 ISNULL(vip.MarketID,0),   
 ISNULL(vip.MMAID,0),
 ISNULL(vip.MAAID,0)

CREATE CLUSTERED INDEX idx_#STIDs ON #aHFS(MarketID,MMAID,MAAID)

SELECT
ISNULL(vip.MarketID,0) MarketID,   
ISNULL(vip.MMAID,0) MMAID,
ISNULL(vip.MAAID,0) MAAID, 
SUM(CONVERT(FLOAT,AvailD)) AvailD,
SUM(CONVERT(FLOAT,AvailN)) AvailN,
SUM(CONVERT(FLOAT,RateD)) RateD,
SUM(CONVERT(FLOAT,RateN)) RateN
INTO #abml
FROM SSA.dbo.AP_KPI2015_BML_ACT t
JOIN #vSIP_Hierarchy vip ON t.hotel_key = vip.HotelKey
WHERE t.date_update =@CurrentQuarterBegin
GROUP BY
 ISNULL(vip.MarketID,0),   
 ISNULL(vip.MMAID,0),
 ISNULL(vip.MAAID,0) 

CREATE CLUSTERED INDEX idx_#STIDs ON #abml(MarketID,MMAID,MAAID)

TRUNCATE TABLE dbo.KPIPulseData_Callidus
INSERT INTO dbo.KPIPulseData_Callidus
SELECT 
   [MarketID]
  ,[MAAID]
  ,[MMAID]
  ,[AsOfBookingDate]
  ,[aNUM_HFS]
  ,[aDENOM_HFS]
  ,[tNUM_HFS]
  ,[tDENOM_HFS]
  ,[QTDCyActualNRN]
  ,[QTDCyActualRMD]
  ,[QTDLyActualNRN]
  ,[QTDLyActualRMD]
  ,[QTDPlanNRN]
  ,[QTDPlanRMD]
  ,[FullQPlanNRN]
  ,[FullQPlanRMD]
  ,[tAcq]
  ,[aAcq]
  ,[tAvailD]
  ,[tAvailN]
  ,[tRateD]
  ,[tRateN]
  ,[aAvailD]
  ,[aAvailN]
  ,[aRateD]
  ,[aRateN]
  ,[pAcq] 
  FROM [ProdReports].[dbo].[KPIPulseData_Snapshot_2015]
WHERE SnapshotQuarterBeginDate = @CurrentQuarterBegin 

UPDATE m
SET 
QTDCyActualNRN = ISNULL(cyprod.NRN,0),
QTDCyActualRMD = ISNULL(cyprod.RMD,0)
FROM [dbo].[KPIPulseData_Callidus] m
LEFT JOIN #CyProd cyprod ON m.MarketID = cyprod.MarketID AND m.MAAID = cyprod.MAAID AND m.MMAID = cyprod.MMAID

INSERT INTO [dbo].[KPIPulseData_Callidus] 
SELECT DISTINCT
	cyprod.MarketID,
	ISNULL(cyprod.MAAID,0) MAAID,
	ISNULL(cyprod.MMAID,0) MMAID,
	@AsofBookingDate,
	0 aNUM_HFS,
	0 aDENOM_HFS,
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
	LEFT JOIN [dbo].[KPIPulseData_Callidus] m ON m.MarketID = cyprod.MarketID AND m.MAAID = cyprod.MAAID AND m.MMAID = cyprod.MMAID
	WHERE m.MARKETID IS NULL

UPDATE m
SET 
aNUM_HFS = ISNULL(ahfs.NUM_HFS,0),
aDENOM_HFS = ISNULL(ahfs.DENOM_HFS,0)
FROM [dbo].KPIPulseData_Callidus m
LEFT JOIN #aHFS ahfs ON m.MarketID = ahfs.MarketID AND m.MAAID = ahfs.MAAID AND m.MMAID = ahfs.MMAID

INSERT INTO [dbo].[KPIPulseData_Callidus] 
SELECT DISTINCT
	ahfs.MarketID,
	ISNULL(ahfs.MAAID,0) MAAID,
	ISNULL(ahfs.MMAID,0) MMAID,
	@AsofBookingDate,
	ISNULL(ahfs.NUM_HFS,0) aNUM_HFS,
	ISNULL(ahfs.DENOM_HFS,0) aDENOM_HFS,
	0 tNUM_HFS,
	0 tDENOM_HFS,
	0 QTDCyActualNRN,
	0 QTDCyActualRMD,
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
	FROM #aHFS ahfs
	LEFT JOIN [dbo].[KPIPulseData_Callidus] m ON m.MarketID = ahfs.MarketID AND m.MAAID = ahfs.MAAID AND m.MMAID = ahfs.MMAID
	WHERE m.MARKETID IS NULL
			
UPDATE m
SET 
aAvailD=ISNULL(abs(abml.AvailD),0),
aAvailN=ISNULL(abs(abml.AvailN),0),
aRateD=ISNULL(abs(abml.RateD),0),
aRateN=ISNULL(abs(abml.RateN),0)
FROM [dbo].[KPIPulseData_Callidus] m
LEFT JOIN #aBML abml ON m.MarketID = abml.MarketID AND m.MAAID = abml.MAAID AND m.MMAID = abml.MMAID

INSERT INTO [dbo].[KPIPulseData_Callidus] 
SELECT DISTINCT
	abml.MarketID,
	ISNULL(abml.MAAID,0) MAAID,
	ISNULL(abml.MMAID,0) MMAID,
	@AsofBookingDate,
	0 aNUM_HFS,
	0 aDENOM_HFS,
	0 tNUM_HFS,
	0 tDENOM_HFS,
	0 QTDCyActualNRN,
	0 QTDCyActualRMD,
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
	ISNULL(aAvailD,0),
	ISNULL(aAvailN,0),
	ISNULL(aRateD,0),
	ISNULL(aRateN,0),
	0 pAcq
	FROM #abml abml
	LEFT JOIN [dbo].[KPIPulseData_Callidus] m ON m.MarketID = abml.MarketID AND m.MAAID = abml.MAAID AND m.MMAID = abml.MMAID
	WHERE m.MARKETID IS NULL
			