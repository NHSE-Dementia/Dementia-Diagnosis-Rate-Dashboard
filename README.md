# Dementia Diagnosis Rate Dashboard

This repository contains the SQL script for the Dementia Diagnosis Rate (DDR) Dashboard, which calculates upper and lower control limits and the pbar for statistical process control (SPC) charts. The output table from this script is used in tableau to produce a dashboard.

A p chart (type of SPC) has been used to monitor changes in the DDR over time using the formulae outlined here: https://sixsigmastudyguide.com/p-attribute-charts/

Data from April 2017 to the lastest available month is used, so two SPC charts are produced. The first looks at the full time period, and the second looks at pre-Covid (March 2020) and post-Covid separately. The latter chart was produced due to a marked decrease in the DDR after March 2020 so it seemed appropriate to calculate control limits separately for these two distinct time periods.
