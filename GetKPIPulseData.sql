USE [ProdReports]
GO
/****** Object:  StoredProcedure [dbo].[GetKPIPulseData]    Script Date: 04/30/2015 14:28:29 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER Proc [dbo].[GetKPIPulseData] --[dbo].[GetKPIPulseData] @SuperRegions = '2',@TerritoryLevelID =60
@SuperRegions varchar(4000) ='2',
@Regions varchar(4000) =Null,
@TerritoryLevelID Int =Null
AS

CREATE TABLE #Markets(MarketID int)

SELECT * INTO #vSIP_Hierarchy FROM dbo.vSIP_Hierarchy 
WHERE 
			SuperRegionID >0

CREATE CLUSTERED INDEX idx_#IDs ON #vSIP_Hierarchy (MarketID,MMAID,MAAID)


IF(ISNULL(@Regions,'')='') -- if no Regions provided
    BEGIN
        IF(ISNULL(@SuperRegions,'')='') -- if no SuperRegions provided
            BEGIN
					INSERT INTO #Markets(MarketID) -- pulls all Markets
					SELECT DISTINCT MarketID FROM #vSIP_Hierarchy 
            END
        ELSE -- there's SuperRegion value
            BEGIN
					INSERT INTO #Markets(MarketID)
					SELECT DISTINCT  MarketID FROM #vSIP_Hierarchy s
						JOIN(SELECT [str] AS SuperRegionID FROM dbo.charlist_to_table(@SuperRegions,DEFAULT)) sr ON s.SuperRegionID = sr.SuperRegionID
			END
    END
    ELSE -- if there'sre Regions provided
    BEGIN
			INSERT INTO #Markets(MarketID)
			SELECT DISTINCT MarketID FROM #vSIP_Hierarchy s
				JOIN(SELECT [str] AS RegionID FROM dbo.charlist_to_table(@Regions,DEFAULT)) sr ON s.RegionID = sr.RegionID
	END
	
	
CREATE CLUSTERED INDEX idx_#MarketID ON #Markets(MarketID)

CREATE TABLE #SIP
(
AMTID INT,AMTName VARCHAR(80),MarketID INT,MarketName VARCHAR(80), RegionName VARCHAR(80),RegionID INT,SMTID INT,SMTName VARCHAR(80),SuperRegionName VARCHAR(80),SuperRegionID INT
)

INSERT INTO #SIP
SELECT DISTINCT AMTID,AMTName,s.MarketID,s.MarketName,RegionName,RegionID,SMTID,SMTName,SuperRegionName,s.SuperRegionID 
FROM #vSIP_Hierarchy s 
	JOIN #Markets m ON m.MarketID = s.MarketID 
/*
SELECT 
DISTINCT AMTID,MarketID
INTO #NoDupes
FROM
(
SELECT
AMTID,MarketID, COUNT(*) HotelCnt,
RANK() OVER(PARTITION BY MarketID ORDER BY COUNT(*) DESC) Rnk
FROM [dbo].[vSIP_Hierarchy ]
GROUP BY AMTID,MarketID
) s
WHERE Rnk = 1

DELETE  s
FROM #SIP s
LEFT JOIN #NoDupes d
ON s.MarketID = d.MarketID AND s.AMTID = d.AMTID
WHERE d.AMTID IS NULL*/
	
CREATE CLUSTERED INDEX idx_#IDs ON #Sip(MarketID)

CREATE TABLE #ST
(
STID INT,STName VARCHAR(80)
)

CREATE TABLE #Acq
(
AMTID INT, tAcq float,aAcq float
)

IF(@TerritoryLevelID = 50)
	BEGIN
		INSERT INTO #ST
		SELECT DISTINCT s.MMAID,MMAName FROM #vSIP_Hierarchy s 
		JOIN #Markets m ON m.MarketID = s.MarketID 
		
		CREATE CLUSTERED INDEX idx_#IDs ON #ST(STID)
		
		SELECT 
		 s.SuperRegionName
		,s.SuperRegionID
		,s.SMTID
		,s.SMTName
		,s.RegionID
		,s.RegionName
		,s.AMTID
		,s.AMTName
		,ISNULL(STID,0) STID 
		,ISNULL(STName,'Unassigned') STName
		,@TerritoryLevelID TerritoryLevelID
		,[AsOfBookingDate]
		,SUM(CASE WHEN ISNULL(hfs.tDENOM_HFS,0) >0 THEN aDENOM_HFS ELSE 0 END) aDENOM_HFS
		,SUM(CASE WHEN ISNULL(hfs.tDENOM_HFS,0) >0 THEN aNUM_HFS ELSE 0 END) aNUM_HFS
		,SUM(k.tDENOM_HFS) tDENOM_HFS 
		,SUM(tNUM_HFS) tNUM_HFS
		,SUM([QTDCyActualNRN]) [QTDCyActualNRN]
		,SUM([QTDCyActualRMD]) [QTDCyActualRMD]
		,SUM([QTDPlanNRN]) [QTDPlanNRN]
		,SUM([QTDPlanRMD]) [QTDPlanRMD]
		,ISNULL(AVG(acq.tAcq),0) tAcq
		,ISNULL(AVG(acq.aAcq),0) aAcq
		,SUM(tAvailD) tAvailD
		,SUM(tAvailN) tAvailN
		,SUM(tRateD) tRateD
		,SUM(tRateN) tRateN
		,SUM(aAvailD) aAvailD
		,SUM(aAvailN) aAvailN
		,SUM(aRateD) aRateD
		,SUM(aRateN) aRateN
		,SUM([QTDLyActualNRN]) [QTDLyActualNRN]
		,SUM([QTDLyActualRMD]) [QTDLyActualRMD]

		FROM #Markets m 
		JOIN [dbo].[KPIPulseData] k ON m.MarketID = k.MarketID
		JOIN #SIP s ON s.MarketID = k.MarketID 
		--JOIN(SELECT [str] AS SuperRegionID FROM dbo.charlist_to_table(@SuperRegions,DEFAULT)) sr ON s.SuperRegionID = sr.SuperRegionID
		LEFT JOIN #ST st ON k.MMAID = st.STID
		LEFT JOIN dbo.KPIAcq acq ON st.STID = acq.MMAID
		LEFT JOIN (SELECT MarketID, SUM(tDENOM_HFS) tDENOM_HFS FROM [dbo].[KPIPulseData] GROUP BY MarketID) hfs ON m.MarketID = hfs.MarketID
		WHERE ISNULL(s.SuperRegionID,0) >0 
		GROUP BY
		 s.SuperRegionName
		,s.SuperRegionID
		,s.SMTID
		,s.SMTName
		,s.RegionID
		,s.RegionName
		,s.AMTID
		,s.AMTName
		,ISNULL(STID,0)
		,ISNULL(STName,'Unassigned')
		,[AsOfBookingDate]
	END
ELSE 
IF(@TerritoryLevelID = 60)
	BEGIN
	
		ALTER TABLE #ST
		ADD AMTID int,Rnk int

		INSERT INTO #ST
		SELECT s.MAAID,s.MAAName,s.AMTID,RANK() OVER(PARTITION BY AMTID ORDER BY MAAID DESC) Rnk
		FROM 
		(
		SELECT DISTINCT s.MAAID,MAAName,AMTID FROM #vSIP_Hierarchy s 
		JOIN #Markets m ON m.MarketID = s.MarketID
		) s

		CREATE CLUSTERED INDEX idx_#IDs ON #ST(STID)
		
		--Acq Targets
		INSERT INTO #Acq
		SELECT
		AMTID
		,ISNULL(SUM(acq.tAcq),0) tAcq
		,ISNULL(SUM(acq.aAcq),0) aAcq
		FROM dbo.KPIAcq acq
		JOIN (SELECT DISTINCT MMAID,AMTID FROM #vSIP_Hierarchy s
				JOIN #Markets m ON m.MarketID = s.MarketID) s
		ON acq.MMAID = s.MMAID
		GROUP BY AMTID
		
		CREATE CLUSTERED INDEX idx_#IDs ON #Acq(AMTID)
		
		SELECT 
		 s.SuperRegionName
		,s.SuperRegionID
		,s.SMTID
		,s.SMTName
		,s.RegionID
		,s.RegionName
		,s.AMTID
		,s.AMTName
		,ISNULL(STID,0) STID
		,ISNULL(STName,'Unassigned') STName
		,@TerritoryLevelID TerritoryLevelID
		,[AsOfBookingDate]
		,SUM(CASE WHEN ISNULL(hfs.tDENOM_HFS,0) >0 THEN aDENOM_HFS ELSE 0 END) aDENOM_HFS
		,SUM(CASE WHEN ISNULL(hfs.tDENOM_HFS,0) >0 THEN aNUM_HFS ELSE 0 END) aNUM_HFS
		,SUM(k.tDENOM_HFS) tDENOM_HFS 
		,SUM(tNUM_HFS) tNUM_HFS
		,SUM([QTDCyActualNRN]) [QTDCyActualNRN]
		,SUM([QTDCyActualRMD]) [QTDCyActualRMD]
		,SUM([QTDPlanNRN]) [QTDPlanNRN]
		,SUM([QTDPlanRMD]) [QTDPlanRMD]
		,AVG(acq.tAcq) tAcq
		,AVG(acq.aAcq) aAcq
		,SUM(tAvailD) tAvailD
		,SUM(tAvailN) tAvailN
		,SUM(tRateD) tRateD
		,SUM(tRateN) tRateN
		,SUM(aAvailD) aAvailD
		,SUM(aAvailN) aAvailN
		,SUM(aRateD) aRateD
		,SUM(aRateN) aRateN
		,SUM([QTDLyActualNRN]) [QTDLyActualNRN]
		,SUM([QTDLyActualRMD]) [QTDLyActualRMD]

		FROM #Markets m 
		JOIN [dbo].[KPIPulseData] k ON m.MarketID = k.MarketID
		JOIN #SIP s ON s.MarketID = k.MarketID
		--JOIN(SELECT [str] AS SuperRegionID FROM dbo.charlist_to_table(@SuperRegions,DEFAULT)) sr ON s.SuperRegionID = sr.SuperRegionID
		LEFT JOIN #ST st ON k.MAAID = st.STID AND st.AMTID = s.AMTID
		LEFT JOIN #Acq acq ON acq.AMTID = st.AMTID AND st.Rnk =1
		LEFT JOIN (SELECT MarketID, SUM(tDENOM_HFS) tDENOM_HFS FROM [dbo].[KPIPulseData] GROUP BY MarketID) hfs ON m.MarketID = hfs.MarketID
		WHERE ISNULL(s.SuperRegionID,0) >0
		GROUP BY
		 s.SuperRegionName
		,s.SuperRegionID
		,s.SMTID
		,s.SMTName
		,s.RegionID
		,s.RegionName
		,s.AMTID
		,s.AMTName
		,ISNULL(STID,0)
		,ISNULL(STName,'Unassigned')
		,[AsOfBookingDate]
	END
ELSE 
IF(@TerritoryLevelID = 70)
	BEGIN
	
		ALTER TABLE #ST
		ADD AMTID int,Rnk int

		INSERT INTO #ST
		SELECT s.*,RANK() OVER(PARTITION BY AMTID ORDER BY MarketID DESC) Rnk
		FROM 
		(
		SELECT DISTINCT s.MarketID,s.MarketName,AMTID FROM #vSIP_Hierarchy s 
		JOIN #Markets m ON m.MarketID = s.MarketID
		) s
		 
		CREATE CLUSTERED INDEX idx_#IDs ON #ST(STID)
		
		--Acq Targets
		INSERT INTO #Acq
		SELECT
		AMTID
		,ISNULL(SUM(acq.tAcq),0) tAcq
		,ISNULL(SUM(acq.aAcq),0) aAcq
		FROM dbo.KPIAcq acq
		JOIN (SELECT DISTINCT MMAID,AMTID FROM #vSIP_Hierarchy s
				JOIN #Markets m ON m.MarketID = s.MarketID) s
		ON acq.MMAID = s.MMAID
		GROUP BY AMTID

		SELECT 
		 s.SuperRegionName
		,s.SuperRegionID
		,s.SMTID
		,s.SMTName
		,s.RegionID
		,s.RegionName
		,s.AMTID
		,s.AMTName
		,ISNULL(s.MarketID,0) STID 
		,ISNULL(MarketName,'UnKnown') STName
		,@TerritoryLevelID TerritoryLevelID
		,[AsOfBookingDate]
		,CASE WHEN SUM(tDENOM_HFS) >0 THEN SUM(aDENOM_HFS) ELSE 0 END aDENOM_HFS
		,CASE WHEN SUM(tDENOM_HFS) >0 THEN SUM(aNUM_HFS) ELSE 0 END aNUM_HFS
		,SUM(tDENOM_HFS) tDENOM_HFS 
		,SUM(tNUM_HFS) tNUM_HFS
		,SUM([QTDCyActualNRN]) [QTDCyActualNRN]
		,SUM([QTDCyActualRMD]) [QTDCyActualRMD]
		,SUM([QTDPlanNRN]) [QTDPlanNRN]
		,SUM([QTDPlanRMD]) [QTDPlanRMD]
		,AVG(acq.tAcq) tAcq
		,AVG(acq.aAcq) aAcq
		,SUM(tAvailD) tAvailD
		,SUM(tAvailN) tAvailN
		,SUM(tRateD) tRateD
		,SUM(tRateN) tRateN
		,SUM(aAvailD) aAvailD
		,SUM(aAvailN) aAvailN
		,SUM(aRateD) aRateD
		,SUM(aRateN) aRateN
		,SUM([QTDLyActualNRN]) [QTDLyActualNRN]
		,SUM([QTDLyActualRMD]) [QTDLyActualRMD]

		FROM #Sip s
		JOIN [dbo].[KPIPulseData] k
		ON k.MarketID = s.MarketID
		--JOIN(SELECT [str] AS SuperRegionID FROM dbo.charlist_to_table(@SuperRegions,DEFAULT)) sr ON s.SuperRegionID = sr.SuperRegionID
		JOIN #ST st ON s.MarketID = st.STID
		LEFT JOIN #Acq acq ON acq.AMTID = st.AMTID AND st.Rnk =1
		WHERE ISNULL(s.SuperRegionID,0) >0 
		GROUP BY
		 s.SuperRegionName
		,s.SuperRegionID
		,s.SMTID
		,s.SMTName
		,s.RegionID
		,s.RegionName
		,s.AMTID
		,s.AMTName
		,ISNULL(s.MarketID,0)
		,ISNULL(MarketName,'UnKnown')
		,[AsOfBookingDate]
	END
