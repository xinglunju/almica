#!/bin/bash

##### Parameters #########################################

# README -------------------------------------------------
#
#
# Latest update: 2019 Nov. 17 by Baobab Liu
#
# Compatible with outputs of CASA 5.4 and Miriad-carma 4.3.8
# For combining spectral line cubes.
#
# This script has been tested with an ALMA mosiac with 46 pointings
# of the 12m-dish observations, 13 pointings of ACA observations,
# and the complementary TP OTF mapping.
# I used to split individual pointings to a separated file,
# and I also asked my colleagues to do so when they need my engagement.
# When troubleshooting the procedure and environment,
# it is useful if we can transfer tarballs of only one and then a few
# pointings.
#
#
# It would be very much appreciated if you can cite
# https://ui.adsabs.harvard.edu/abs/2013ApJ...770...44L/abstract
# when using this script
#
# This task has been a nightmare for many people.
# It is recommended that you try to understand what individual steps
# are doing (down to the level of individual parameters) before you
# feel comfortable to run it blindly.
#
# The Flow Control section allow you to set which step(s) you
# would like to (re-)execute. When you use this procedure for the first time,
# it is recommended that you enable one step at a time and make sure it works
# and you know how it works.
#
# If you feel this script is hard to follow, you can look into the
# combine_single.sh script first, which is to combine single-pionting observations
# of ACA and TP.
#
# When encoutering any problem, you are more than welcome to contact me.
#
# Flow ---------------------------------------------------
#
# 1. Convert input data from FITS to Miriad format 
#
# 2. Correct headers if necessary
#
# 3. Generate TP visibilities at ACA pointings
#
# 4. Jointly image ACA and TP visibilities
#
# 5. Re-generate ACA+TP visibilities at 12m pointings
#
# 6. Final imaging
#
# --------------------------------------------------------


# flow control -------------------------------------------
# Feel free to remove the explanation to make this section concise.
#
#   converting FITS files to Miriad format files
if_fitstomiriad='yes'
#   modify headers (important and hard when you're combining
#   data taken from different observatories).
if_setheaders='yes'
#   deconvolve single-dish image. Miriad allows you to use
#   MEM or clean to do this. However, MEM is somewhat tricky
#   to control for unexperienced users. If you are not familiar
#   with image deconvolution, it is better to use clean.
if_tpdeconvolve='yes'
#   convert single dish (i.e., total-power or tp) image to visibility
if_tp2vis='yes'
#   re-weight the total power visibility by adjusting tsys artificially
if_tprewt='yes'
#   duplicate the ACA and TP visibilities and move them to a isolated folder.
#   This is convenient for the scripted imaging in the later time.
#   The filesize is not big anyway.
if_duplicateACATP='yes'
#   creating ACA + TP image
if_acaim='yes'
#   rescale the flux density of the ACA+TP clean model.
#   This is in case of absolute flux calibration errors.
#   If this is not a concern, simply use a scaling factor 1.0.
if_acatpscale='yes'
#   convert the ACA+TP clean model to ALMA visibility.
if_tp2almavis='yes'
#   reweight the ACA+TP visibility model before jointly imaging with the
#   ALMA 12m-dish data (i.e., artificially adjusting the Tsys parameter).
if_acatprewt='yes'
#   Duplicate all visibility files to a isolated folder before
#   jointly imaging all data.
if_duplicateALL='yes'
#   Producing the final image. I recommend to continue doing this within
#   Miriad since it is fast. You can also do the following steps in CASA
#   if that is what you prefer. Those are normal imaging steps.
if_finalim='yes'
#   Removing some files that were produced in the steps,
#   which are useful for troubleshooting but not for science analysis.
#   Some of those are image cubes and can have very big sizes.
if_cleanup='yes'
#   Linearly combine the single-dish image for one last time.
#   This is useful since clean does not conserve total flux in general.
if_reimmerge='yes'
#
# --------------------------------------------------------


# global information -------------------------------------
#  set a rest frequency of your spectral line.
#  The velocity grids will depend on this.
linerestfreq='87.925238' # in GHz unit

# set the starting channel and total number of channels.
# When you're running the script for the first time,
# it is recommended that you only image 1 or 2 channels around your spectral peak
# and adjust the relative weighting based on this initial trial.
ch_start="900"
numch="100"

# set the cellsize and dimension for the ACA images
# The cellsize times the imsize, which is the map size in arcsec,
# should be about twice the primary beam size -- xlu
aca_cell=2.4
aca_imsize=100

# parameters for deconvolving the TP image
cutoff_tp=0.2
niters_tp=1000

# parameters for tp2vis
# to plot and examine the visibility, you can use the Miriad command:
# uvplt vis=single_input.alma_0.uvmodel.miriad axis=uvdis,amp device=/xw options=nobase,avall interval=99999 nxy=1,1 line=channel,15,1,1,1
npts=100     # number of visibility points to use when running uvrandom
uvmax=24.    # maximum uv distance, in nanosecs. 24 nanoseconds = 7.2 m = 2.4 klambda

# parameters for tp2almavis
# to plot and examine the visibility, you can use the Miriad command:
# uvplt vis=alma_co_2to1.0.uv.miriad axis=uvdis,amp device=/xw options=nobase,avall interval=99999 nxy=1,1 line=channel,15,1,1,1
nptsalma=3000 # number of visibility points to use when running uvrandom
uvmaxalma=18  # maximum uv distance


# --------------------------------------------------------

# 12m data information
path_12m='../../calibrated_TM1/'
name_12m='alma_hnco'
fields_12m=$(seq 0 1 189)  # set the iterator to loop from pointing 0 to 45
pbfwhm_12m='68.06' # Measured from the pb file in the QA2 package...

# 7m data information
path_7m='../../calibrated_7m/'
name_7m='aca_hnco'
fields_7m=$(seq 0 1 195)   # set the iterator to loop from pointing 0 to 12
pbfwhm_7m='117.8' # Measured from the pb file in the QA2 package...

# TP data information
path_tp='../../calibrated_TP/product/'
name_tp='spw23.cube.I.sd.vel'
pbfwhm_tp='73.974' # This is from the header of the TP FITS image
## The following three parameters are tricky!!!
crval3_tp=-106.5285343 # reset velocity header (important if this is not ALMATP)
cdelt3_tp=0.104046788   # reset velocity header (important if this is not ALMATP)
crpix3_tp=1             # reset velocity header (important if this is not ALMATP)
##
tsys_tp=6500.0          # an artificial tsys for relative weighting
tp_unit_convert="yes"
tp_brightness_unit="Jy/beam"
tp_conv_f=1.0  # a constant to multiple to all pixels of your TP image.
tp_add_f=0.0   # a constant to add to all pixels of your TP image.


# - - Defining global variables - - - - - - - - - - - - -#
ch='channel,'$numch','$ch_start',1,1'  # <- changed by xlu
chout='channel,'$numch','$ch_start',1,1'

# ACA+TP imaging parameter
acatp_niters=1000
acatp_cutoff=0.3 # rms is about 0.1 from dirty map
acatp_method='clean'

# 12m + (ACA+TP) imaging parameter
#tsys_acatp=11000.0
## Final beam size is too large. Use a higher Tsys for ACA+TP to make it smaller?
tsys_acatp=20000.0
alma_cell=0.28
alma_imsize=512
cutoff_alma=0.01
niters_alma=1000
imaging_method='clean'
#acatp_conv_f=0.03515625  # set this value to be ( alma_cell / aca_cell )^2
acatp_conv_f=0.013611111  # set this value to be ( alma_cell / aca_cell )^2

##########################################################



##### Converting FITS data to Miriad format ##############
# You might need to edit this section if your naming
# syntax is different from mine.

if [ $if_fitstomiriad == 'yes' ] 
then

   # 12m data
   echo '########## Importing 12m data ##########'
   for field_id in $fields_12m
     do 
	outname=$name_12m'.'$field_id'.uv.miriad'
	rm -rf $outname
        fits in=$path_12m$name_12m'.'$field_id'.uv.fits'  \
	     op=uvin \
	     out=$outname
	     #op=uvin velocity=lsr,0.04538,961 line=velocity,1920,99.99641888875,0.10411566564247077,1 \
         # This does not seem to make any difference... --xlu
     done

   # 7m data
   echo '########## Importing ACA data ##########'
   for field_id in $fields_7m
     do
        outname=$name_7m'.'$field_id'.uv.miriad'
        rm -rf $outname
        fits in=$path_7m$name_7m'.'$field_id'.uv.fits'  \
             op=uvin \
             out=$outname
     done

   # TP
   echo '########## Importing TP data ##########'
   outname=$name_tp'.image.miriad'
   rm -rf $outname
   fits in=$path_tp$name_tp'.fits' \
	op=xyin \
	out=$outname

fi

##########################################################



##### Reset headers to allow Miriad processing ###########
#
# This step is usually the most frustrating,
# especially when you are combining single-dish image
# that is not taken with ALMA TP.
#


if [ $if_setheaders == 'yes' ]
then

   # 12m data (set the primary beam)
   # this step is necessary for certain distributions of Miriad
   # (i.e., in case it does not recognize ALMA, ACA, or TP)
   for field_id in $fields_12m
     do
        pb="gaus("$pbfwhm_12m")"
        puthd in=$name_12m'.'$field_id'.uv.miriad'/telescop \
              value='single' type=a
        puthd in=$name_12m'.'$field_id'.uv.miriad'/pbtype \
              value=$pb type=a
     done

   # 7m data (set the primary beam)
   # this step is necessary for certain distributions of Miriad
   # (i.e., in case it does not recognize ALMA, ACA, or TP)
   for field_id in $fields_7m
     do
        pb="gaus("$pbfwhm_7m")"
        puthd in=$name_7m'.'$field_id'.uv.miriad'/telescop \
            value='single' type=a
	    puthd in=$name_7m'.'$field_id'.uv.miriad'/pbtype \
            value=$pb type=a
     done

   # TP (set beam size and velocity headers)
   # Note that by default miriad outputs beam sizes in radians (in gethd etc.)
   puthd in=$name_tp'.image.miriad'/bmaj value=$pbfwhm_tp,arcsec type=double
   puthd in=$name_tp'.image.miriad'/bmin value=$pbfwhm_tp,arcsec type=double
   puthd in=$name_tp'.image.miriad'/bpa  value=0,degree type=double
   puthd in=$name_tp'.image.miriad'/ctype3 value='VELO-LSR' type=ascii
   #puthd in=$name_tp'.image.miriad'/cunit3 value='m/s   ' type=ascii
   puthd in=$name_tp'.image.miriad'/crval3 value=$crval3_tp type=double
   puthd in=$name_tp'.image.miriad'/cdelt3 value=$cdelt3_tp type=double
   puthd in=$name_tp'.image.miriad'/crpix3 value=$crpix3_tp type=double
   # The above three changes are necessary, because miriad always takes cunits as km/s
   # regardless of how we change the header --xlu

   pb="gaus("$pbfwhm_tp")"
   puthd in=$name_tp'.image.miriad'/telescop \
            value='single' type=a
   puthd in=$name_tp'.image.miriad'/pbtype \
            value=$pb type=a


   # apply a multiplication constant tp_conv_f to the TP image
   rm -rf single_input.miriad
   if [ $tp_unit_convert == 'yes' ]
   then
     maths exp="(($name_tp.image.miriad)*$tp_conv_f)" \
	   out=single_input.miriad options=unmask
   else
     cp -r $name_tp'.image.miriad' single_input.miriad
   fi

   puthd in=single_input.miriad/bmaj value=$pbfwhm_tp,arcsec type=double
   puthd in=single_input.miriad/bmin value=$pbfwhm_tp,arcsec type=double
   puthd in=single_input.miriad/bpa  value=0,degree type=double
   puthd in=single_input.miriad/bunit value='Jy/beam' type=ascii
   puthd in=single_input.miriad/ctype3 value='VELO-LSR' type=ascii
   puthd in=single_input.miriad/crval3 value=$crval3_tp type=double
   puthd in=single_input.miriad/cdelt3 value=$cdelt3_tp type=double
   puthd in=single_input.miriad/crpix3 value=$crpix3_tp type=double

fi

##########################################################



##### Deconvolve TP map ##################################

if [ $if_tpdeconvolve == 'yes' ]
then

   # Generate the TP Gaussian Beam
   rm -rf tp_beam
   imgen out=tp_beam imsize=$aca_imsize cell=$aca_cell \
         object=gaussian \
         spar=1,0,0,$pbfwhm_tp,$pbfwhm_tp,0


   for field_id in $fields_7m
     do
        # Creat template ACA maps for regriding TP maps
        rm -rf single_input.aca_$field_id.temp.miriad
        rm -rf temp.beam
	    echo $ch
        invert vis=$name_7m'.'$field_id'.uv.miriad'   \
           imsize=$aca_imsize cell=$aca_cell options=double \
           map=single_input.aca_$field_id.temp.miriad beam=temp.beam line=$ch

        # Added by xlu: change the spectral info in header. From topo () to lsr
        puthd in=single_input.aca_$field_id.temp.miriad/ctype3 value='VELO-LSR' type=ascii
        puthd in=single_input.aca_$field_id.temp.miriad/specsys value='LSRK' type=ascii

	    # Regrid TP maps
        rm -rf single_input.aca_$field_id.regrid.miriad       
        regrid in=single_input.miriad tin=single_input.aca_$field_id.temp.miriad \
           out=single_input.aca_$field_id.regrid.miriad \
           project=sin #axes=3

        # Deconvolve the TP Map
	    rm -rf single_input.aca_$field_id.deconv.miriad
        clean map=single_input.aca_$field_id.regrid.miriad beam=tp_beam \
            out=single_input.aca_$field_id.deconv.miriad \
            niters=$niters_tp cutoff=$cutoff_tp gain=0.05

	    # Restore the deconvolved TP map for a sanity check
	    rm -rf single_input.aca_$field_id.restor.miriad
        restor map=single_input.aca_$field_id.regrid.miriad beam=tp_beam \
           model=single_input.aca_$field_id.deconv.miriad \
           mode=clean out=single_input.aca_$field_id.restor.miriad
        # Use the following comand to check the maps --xlu
        # cgdisp in=single_input.aca_0.restor.miriad device=/xs nxy=2,2 options=3pixel,3value

        rm -rf single_input.aca_$field_id.residual.miriad
        restor map=single_input.aca_$field_id.regrid.miriad beam=tp_beam \
           model=single_input.aca_$field_id.deconv.miriad \
           mode=residual out=single_input.aca_$field_id.residual.miriad

	    # Apply the ACA primary beam to TP clean models
	    rm -rf temp1
	    rm -rf single_input.aca_$field_id.demos.miriad
        demos map=single_input.aca_$field_id.deconv.miriad vis=$name_7m'.'$field_id'.uv.miriad' \
           out=temp
	    mv temp1 single_input.aca_$field_id.demos.miriad

        # Regrid RA/Dec of the demos image
        #regrid in=temp1 tin=single_input.aca_$field_id.temp.miriad \
        #   out=single_input.aca_$field_id.demos.miriad axes=1,2
        #rm -rf temp1
     done

     # clean up
     rm -rf temp.beam
     rm -rf tp_beam
     rm -rf single_input.aca_*.temp.miriad

fi

##########################################################



##### Convolve TP map to visibility ######################

if [ $if_tp2vis == 'yes' ]
then

   rm -rf uv_random.miriad
   uvrandom npts=$npts freq=$linerestfreq inttime=10.0808 uvmax=$uvmax nchan=$numch \
            gauss=false out=uv_random.miriad
   # Check gauss from true to false to have a more realistic uv sampling?? -- xlu
   # Also change uvmax to 24 (nanosecs), which is 7 m? --xlu

   # Plot the uv distribution for a sanity check
   #uvplt vis=uv_random.miriad axis=uc,vc device=/xw options=nobase,avall interval=99999 nxy=1,1 line=channel,15,1,1,1

   for field_id in $fields_7m
     do

#        rm -rf single_input.aca_$field_id'.regrid.miriad'
#        regrid in=single_input.aca_$field_id.demos.miriad \
#               tin=single_input.alma_$field_id.temp.miriad \
#               out=single_input.alma_$field_id.regrid.miriad \
#               project=sin

	    rm -rf single_input.aca_$field_id.uvmodel.miriad
#        uvmodel vis=uv_random.miriad model=single_input.aca_$field_id.demos.miriad \
#                'select=uvrange(0,13)' options=replace,imhead \
#                out=single_input.aca_$field_id.uvmodel.miriad
        uvmodel vis=uv_random.miriad model=single_input.aca_$field_id.demos.miriad \
             options=replace,imhead \
             out=single_input.aca_$field_id.uvmodel.miriad "select=uvnrange(0,$uvmax)"
        ## Change uvrange to uvnrange --xlu
        # Use the following command to check the uv distributions
        # uvplt vis=single_input.aca_0.uvmodel.miriad axis=uc,vc device=/xw options=nobase,avall interval=99999 nxy=1,1 line=channel,1,1,1,1

        rm -rf temp
        uvputhd vis=single_input.aca_$field_id.uvmodel.miriad hdvar='telescop' \
		    varval='TP  ' type=a out=temp
        rm -rf single_input.aca_$field_id.uvmodel.miriad
        mv temp single_input.aca_$field_id.uvmodel.miriad
     done

fi

##########################################################



##### Manually reweight the TP visibilities ##############
if  [ $if_tprewt == 'yes' ]
then

   echo '##### Reweighting TP visibility assuming Tsys ='$tsys_tp' Kelvin'

   for field_id in $fields_7m
     do

	 outname=single_input.aca_$field_id.uvmodel.rewt.miriad
     rm -rf $outname
     uvputhd vis=single_input.aca_$field_id.uvmodel.miriad hdvar=systemp type=r length=1 \
		 varval=$tsys_tp out=$outname
	 #puthd in=$outname/jyperk value=1.0 type=r
	 puthd in=$outname/jyperk value=40.7 type=r # change to 40.7, to be consistent with 7M data

     # Check the result of uvputhd --xlu
     # varplt vis=single_input.aca_$field_id.uvmodel.rewt.miriad log=test.log.txt xaxis=time yaxis=systemp
     # OR
     # uvlist vis=single_input.aca_$field_id.uvmodel.rewt.miriad options=full,variables

	 pb="gaus("$pbfwhm_7m")"
     puthd in=$outname/telescop \
         value='single' type=a
     puthd in=$outname/pbtype \
         value=$pb type=a

     done

fi

##########################################################




##### Make a copy of relevant files for imaging ##########
if [ $if_duplicateACATP == 'yes' ]
then

   rm -rf intermediate_vis
   mkdir intermediate_vis

   # ACA
   for field_id in $fields_7m
     do
       cp -r $name_7m'.'$field_id'.uv.miriad' ./intermediate_vis/Xcloud_7m'.'$field_id.uv.miriad
     done

   # TP
   cp -r single_input.aca_*.uvmodel.rewt.miriad ./intermediate_vis/
 
   # Commpare the TP and 7M visibilities --xlu
    ## 1. Make sure the parameters are consistent, e.g. inttime, systemp, jyperk
    #uvlist vis=single_input.aca_0.uvmodel.rewt.miriad options=full,variables
    #uvlist vis=aca_hnco.0.uv.miriad options=full,variables
    ## 2. Plot the uv plane, make sure the two uv datasets overlap well
    #uvplt vis=aca_hnco.0.uv.miriad  device=1/xs axis=uc,vc options=nobase xrange=-5,5 yrange=-5,5
    #uvplt vis=single_input.aca_0.uvmodel.rewt.miriad device=2/xs axis=uc,vc options=nobase,nanosec xrange=-5,5 yrange=-5,5
    ## 3. Check the amplitude, make sure the two datasets have similar amp where they overlap
    #uvamp vis=aca_hnco.0.uv.miriad device=1/xs line=channel,1,60,1,1 bin=20,6
    #uvamp vis=single_input.aca_0.uvmodel.rewt.miriad device=2/xs line=channel,1,60,1,1 bin=20,6

fi
##########################################################



##### Imaging ACA and TP visibilities together ###########
if [ $if_acaim == 'yes' ]
then


   rm -rf acatp.map
   rm -rf acatp.beam
   #invert "vis=./intermediate_vis/*" options=systemp,double,mosaic \
   #	  map=acatp.map beam=acatp.beam cell=$aca_cell imsize=$aca_imsize robust=2.0
   ## The wildcard does not work, so I used a file list -- xlu 23/1/5
   invert vis=@vislist.txt options=systemp,double,mosaic \
	  map=acatp.map beam=acatp.beam cell=$aca_cell imsize=$aca_imsize robust=0.0

   rm -rf acatp.model
   if [ $acatp_method == 'clean' ]
   then
       mossdi map=acatp.map beam=acatp.beam out=acatp.model gain=0.1 \
	      niters=$acatp_niters cutoff=$acatp_cutoff options=positive
   else
       mosmem map=acatp.map beam=acatp.beam out=acatp.model rmsfac=1.5 
   fi

   rm -rf acatp.clean
   rm -rf acatp.residual
   restor map=acatp.map beam=acatp.beam model=acatp.model \
      mode=clean out=acatp.clean
   restor map=acatp.map beam=acatp.beam model=acatp.model \
      mode=residual out=acatp.residual
   rm -rf acatp.beam.fits
   fits in=acatp.beam op=xyout out=acatp.beam.fits
   fits in=acatp.clean op=xyout out=acatp.clean.fits

   ####
   # Beam size is 60 arcsec, which is too large!
   ####

fi
##########################################################



##### Final ACA+TP flux scaling ##########################

if [ $if_acatpscale == 'yes' ]
then
 
   rm -rf temp
   maths exp="((acatp.model)*$acatp_conv_f)" \
         out=temp options=unmask
   rm -rf acatp.model
   mv temp acatp.model

fi

##########################################################


##### Converting ACA+TP image to 12m visibilities ########
if [ $if_tp2almavis == 'yes' ]
then

   rm -rf uv_random.miriad
   uvrandom npts=$nptsalma freq=$linerestfreq inttime=10 uvmax=$uvmaxalma nchan=$numch \
        gauss=true out=uv_random.miriad

   # Temparily change the 'ch' definiation here
   # Because the TM1 data have less channels than 7M/TP (1920 vs 2048)
   # So the channel indices are different
   # Ultimately, we need to regrid the TM1/7M/TP data to a common frequency axis beforehand
   # --xlu
   ch=channel,80,850,1,1
   for field_id in $fields_12m
     do

    	rm -rf single_input.alma_$field_id.temp.miriad
    	rm -rf temp.beam
        invert vis=$name_12m'.'$field_id'.uv.miriad'   \
               imsize=$alma_imsize cell=$alma_cell \
               map=single_input.alma_$field_id.temp.miriad beam=temp.beam line=$ch

        # applying ALMA primary beam to ACA+TP clean model
	    rm -rf acatp.demos
	    rm -rf acatp.demos1

	    if [ $acatp_method == 'clean' ]
        then
            demos map=acatp.model vis=$name_12m'.'$field_id'.uv.miriad' out=acatp.demos
        else
            demos map=acatp.model vis=$name_12m'.'$field_id'.uv.miriad' out=acatp.demos # options=detaper
        fi

	    mv acatp.demos1 acatp.demos

        # Added by xlu: change the spectral info in header. From topo (or something else?) to lsr
        puthd in=single_input.alma_$field_id.temp.miriad/ctype3 value='VELO-LSR' type=ascii
        puthd in=single_input.alma_$field_id.temp.miriad/specsys value='LSRK' type=ascii
        puthd in=acatp.demos/ctype3 value='VELO-LSR' type=ascii
        puthd in=acatp.demos/specsys value='LSRK' type=ascii

        # regrid ACA+TP maps
        rm -rf single_input.alma_$field_id'.regrid.miriad'
        regrid in=acatp.demos tin=single_input.alma_$field_id.temp.miriad \
               out=single_input.alma_$field_id.regrid.miriad \
               project=sin

	    # simulate visibilities
	    rm -rf single_input.alma_$field_id.uvmodel.miriad
        uvmodel vis=uv_random.miriad model=single_input.alma_$field_id.regrid.miriad \
		    options=replace,imhead "select=uvrange(0,$uvmaxalma)" \
            out=single_input.alma_$field_id.uvmodel.miriad

        rm -rf temp
        uvputhd vis=single_input.alma_$field_id.uvmodel.miriad hdvar='telescop' \
            varval='ALMA' type=a out=temp
        rm -rf single_input.alma_$field_id.uvmodel.miriad
        mv temp single_input.alma_$field_id.uvmodel.miriad

	    outname=single_input.alma_$field_id.uvmodel.miriad
        pb="gaus("$pbfwhm_12m")"
        puthd in=$outname/telescop \
              value='single' type=a
        puthd in=$outname/pbtype \
              value=$pb type=a

     done

fi
##########################################################



##### Manually reweight the ACA+TP visibilities ##########
if  [ $if_acatprewt == 'yes' ]
then

   echo '##### Reweighting ACA+TP visibility assuming Tsys ='$tsys_acatp' Kelvin'

   for field_id in $fields_12m
     do

         outname=single_input.alma_$field_id.uvmodel.rewt.miriad
         rm -rf $outname
         uvputhd vis=single_input.alma_$field_id.uvmodel.miriad hdvar=systemp type=r length=1 \
                 varval=$tsys_acatp out=$outname
         puthd in=$outname/jyperk value=1.0 type=r

         pb="gaus("$pbfwhm_12m")"
         puthd in=$outname/telescop \
               value='single' type=a
         puthd in=$outname/pbtype \
               value=$pb type=a

         # Added by xlu -- force the spec frame to be LSRK
         puthd in=$outname/ctype3 value='VELO-LSR' type=ascii
         puthd in=$outname/specsys value='LSRK' type=ascii

     done

fi

##########################################################



##### Duplicating all visibilities for imaging ###########
if [ $if_duplicateALL == 'yes' ]
then

   rm -rf final_vis
   mkdir final_vis

   # 12m
   for field_id in $fields_12m
     do
       cp -r $name_12m'.'$field_id'.uv.miriad' ./final_vis/'alma.'$field_id'.miriad'
       cp -r single_input.alma_$field_id'.uvmodel.rewt.miriad' ./final_vis/'aca.'$field_id'.miriad'

     done

fi
##########################################################



##### Final imaging ######################################
if [ $if_finalim == 'yes' ]
then

   rm -rf combined.map
   rm -rf combined.beam
   invert vis=@finallist.txt options=systemp,double,mosaic \
          map=combined.map beam=combined.beam cell=$alma_cell imsize=$alma_imsize robust=0.0

   rm -rf combined.model
   if [ $imaging_method == 'clean' ]
   then
       mossdi map=combined.map beam=combined.beam out=combined.model gain=0.1 \
              niters=$niters_alma cutoff=$cutoff_alma
   else
       mosmem map=combined.map beam=combined.beam out=combined.model rmsfac=3 # niters=15
   fi

   rm -rf combined.clean
   rm -rf combined.residual
   restor map=combined.map beam=combined.beam model=combined.model \
          mode=clean out=combined.clean
   restor map=combined.map beam=combined.beam model=combined.model \
          mode=residual out=combined.residual

   puthd in=combined.clean/ctype3 value='VELO-LSR' type=ascii

   rm -rf combined.clean.fits
   fits in=combined.clean op=xyout out=combined.clean.fits
   rm -rf combined.dirty.fits
   fits in=combined.map op=xyout out=combined.dirty.fits
   rm -rf combined.model.fits
   fits in=combined.model op=xyout out=combined.model.fits
   rm -rf combined.residual.fits
   fits in=combined.residual op=xyout out=combined.residual.fits
   rm -rf combined.beam.fits
   fits in=combined.beam op=xyout out=combined.beam.fits


fi
##########################################################



##### Removing meta data #################################
if [ $if_cleanup == 'yes' ]
then
   echo '##### Removing meta data #############'
   rm -rf ./*uvmodel*
   rm -rf ./*regrid*
   rm -rf ./*temp*
   rm -rf ./single_input.miriad
   rm -rf ./single_input*.restor.miriad
   rm -rf ./single_input*.residual.miriad
   rm -rf ./temp.*
   rm -rf ./*.temp
   rm -rf ./uv_random.miriad
   rm -rf ./acatp*
   rm -rf ./intermediate_vis
   rm -rf ./*demos*
   rm -rf ./*deconv*
fi
##########################################################



##### Re-immerge #########################################

if [ $if_reimmerge == 'yes' ]
then


   # Gegrid TP maps
   rm -rf TP.vel.image.regrid.miriad
   regrid in=$name_tp'.image.miriad' tin=combined.clean \
          out=TP.vel.image.regrid.miriad \
          project=sin

   rm -rf combined.clean.reimmerge
   immerge in=combined.clean,TP.vel.image.regrid.miriad factor=1.0 \
	   out=combined.clean.reimmerge

   rm -rf combined.clean.reimmerge.fits
   fits in=combined.clean.reimmerge op=xyout out=combined.clean.reimmerge.fits

fi

##########################################################
