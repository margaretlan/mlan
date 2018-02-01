USE SB_PA_MARGARET
GO

DROP TABLE #ALL; 
DROP TABLE #STATUS;


WITH CHECK_STATUS AS (

SELECT [Account #] ACCT_NBR, [BISYS #] BISYS_NBR_FMT, [Orig LTV] AS ORIG_LTV, 
		[Original FICO], [Current FICO], [CHECK] AS STATUS, 'AFS' AS SRC_TYPE_CD
FROM [dbo].[AFS_CHECK_STATUS_123117]

UNION

SELECT [Account #] ACCT_NBR, [Account #] BISYS_NBR_FMT, [Original LTV Used] AS ORIG_LTV, 
		[Original FICO], [Current FICO], CHECKED AS STATUS, 'ML' AS SRC_TYPE_CD
FROM [dbo].[ML_CHECK_STATUS_123117]

UNION

SELECT [Account No# (0002)] ACCT_NBR, [Account No# (0002)] BISYS_NBR_FMT, [Final LTV] AS ORIG_LTV, 
		[Original FICO], [Current FICO], [Manually Checked?] AS STATUS, 'IL' AS SRC_TYPE_CD
FROM [dbo].IL_CHECK_STATUS_123117

)


SELECT * INTO #STATUS FROM CHECK_STATUS ;


SELECT EOM.DATE_KEY
	  ,EOM.SRC_TYPE_CD
	  ,EOM.Acct_Nbr
	  ,EOM.Bisys_Nbr_Fmt
	  ,EOM.Balance_Sheet_Category
	  --,EOM.ORIG_BALANCE
	  ,EOM.FICO_CURR
	  ,EOM.Lien_Position
	  ,EOM.ORIG_DT
	  ,CASE
	   WHEN EOM.Balance_Sheet_Category in ('Commercial Real Estate Mtgs','Multifamily Mtgs 5+ Units')
			THEN IIF(IP.[BorGtr_FICO] IS NULL, A15738_MinFICO, IP.[BorGtr_FICO])
	   ELSE PL.A15738_MinFICO
	   END AS ORIG_FICO
	  ,CASE 
	   WHEN EOM.Balance_Sheet_Category in ('Commercial Real Estate Mtgs','Multifamily Mtgs 5+ Units')
			THEN IP.[LTV_Final]
	   WHEN EOM.Lien_Position=1
			THEN IIF(EMP.[Customer_key] IS NULL, PLF.ELTV, EMP.ELTV)
	   ELSE IIF(EMP.[Customer_key] IS NULL, PLF.ECLTV, EMP.ECLTV)
	   END AS ORIG_LTV   
	  ,#STATUS.STATUS AS [CHECK_STATUS]   	        
      ,CASE WHEN #STATUS.ACCT_NBR IS NOT NULL THEN 'Y' ELSE 'N' END AS [INCLUDED]

	   INTO #ALL

  FROM [RDM_Loan].[ADJ].[V_LOAN_GL_RECONCILED_EOM] EOM
  LEFT JOIN [PLProd].[dbo].[vw_powerlender] PL
	ON PL.A304_CustomerKey =
		CASE 
		WHEN SUBSTRING(EOM.Bisys_Nbr_Fmt,4,1)='7'
			 THEN '0' + SUBSTRING(EOM.Bisys_Nbr_Fmt,4,6) + RIGHT(EOM.Bisys_Nbr_Fmt,1)
		ELSE 
			 RIGHT(EOM.Bisys_Nbr_Fmt,8)
		END
  LEFT JOIN [PLProd].[dbo].[vw_LoanFacts] PLF
	ON PLF.Loan_Key =
		CASE 
		WHEN SUBSTRING(EOM.Bisys_Nbr_Fmt,4,1)='7'
			 THEN LEFT(EOM.Bisys_Nbr_Fmt,2) + '-0' + SUBSTRING(EOM.Bisys_Nbr_Fmt,4,6) + RIGHT(EOM.Bisys_Nbr_Fmt,1)
		ELSE 
			 EOM.Bisys_Nbr_Fmt
		END
  LEFT JOIN [PLProd_EMPLOYEE].[dbo].[VW_LOAN_FACT_EMP_CUSO] EMP
	ON EMP.[Customer_key] =
		CASE 
		WHEN SUBSTRING(EOM.Bisys_Nbr_Fmt,4,1)='7'
			 THEN '0' + SUBSTRING(EOM.Bisys_Nbr_Fmt,4,6) + RIGHT(EOM.Bisys_Nbr_Fmt,1)
		ELSE 
			 RIGHT(EOM.Bisys_Nbr_Fmt,8)
		END
  LEFT JOIN [CREMF].[dbo].[CRE_Collateral] IP
    ON right(EOM.Bisys_Nbr_Fmt,8)=IP.[BisysNo_Short] 
  LEFT JOIN #STATUS 
	ON #STATUS.ACCT_NBR = CASE WHEN EOM.SRC_TYPE_CD = 'AFS' THEN EOM.Acct_NbR ELSE EOM.Bisys_Nbr_Fmt END

  Where EOM.Date_Key=20171231 AND EOM.SRC_TYPE_CD in ('AFS','ML','IL') AND Status_Description='OPEN'
  --AND EOM.BALANCE_SHEET_CATEGORY in ('Commercial Real Estate Mtgs','Construction Loans','Home Equity Lines of Credit',
  --'Investor','Loans Held for Sale','MF / Comm''l Construction','Multifamily Mtgs 5+ Units','SFR Construction Loans',
  --'Single Family Mtgs 1-4 Units')
  ORDER BY SRC_TYPE_CD, Balance_Sheet_Category, ORIG_LTV DESC
  ;

  UPDATE A
  SET --A.[INCLUDED] = CASE WHEN #STATUS.ACCT_NBR IS NOT NULL THEN 'Y' ELSE 'N' END,
		--A.CHECK_STATUS = CASE WHEN #STATUS.ACCT_NBR IS NOT NULL THEN #STATUS.STATUS ELSE 'NA' END ,
		A.ORIG_LTV = IIF(A.ORIG_LTV IS NULL, #STATUS.ORIG_LTV , A.ORIG_LTV),
		A.ORIG_FICO = IIF(A.ORIG_FICO IS NULL, #STATUS.[Original FICO] , A.ORIG_FICO),
		A.FICO_CURR = IIF(A.FICO_CURR IS NULL, #STATUS.[Current FICO] , A.FICO_CURR) 
  FROM #ALL A  
  LEFT JOIN #STATUS ON #STATUS.ACCT_NBR = CASE 
								WHEN A.SRC_TYPE_CD = 'AFS' THEN A.Acct_NbR
								ELSE A.Bisys_Nbr_Fmt END
  ;
  
  SELECT * FROM #ALL
  WHERE SRC_TYPE_CD = 'AFS'
	AND INCLUDED = 'Y';

  SELECT * FROM #ALL
  WHERE SRC_TYPE_CD = 'ML'
	AND INCLUDED = 'Y';

  SELECT * FROM #ALL
  WHERE SRC_TYPE_CD = 'IL'
	AND INCLUDED = 'Y';