# matlab-hardware-drivers

A collection of hardware drivers written in MATLAB, primarily related to control and measurement using automated microscopy.

## Installation

Most drivers can be used independently. Usage is given in each class.

## Drivers included

- **[Acton 2150 spectrometer](https://www.princetoninstruments.com/wp-content/uploads/2020/04/SpectraPro_Datasheet.pdf)** acton2150.m
- **[Attocube ANC350 controller](https://www.attocube.com/downloads/anc350-piezo-motion-und-readout-controller.pdf)** anc350.m
- **[Thor Labs elliptec controller](https://www.thorlabs.com/newgrouppage9.cfm?objectgroup_id=10122)** ellptec_driver.m
- **[Data Translation USB ADC](https://www.mccdaq.com/Data-Translation/multifunction)** ADC_dotnet.m
- **[Zurich Instruments HF2LI](https://www.zhinst.com/europe/en/products/hf2li-lock-in-amplifier)** hf2li.m
- **[Keithley picoammeter](https://www.tek.com/en/products/keithley/low-level-sensitive-and-specialty-instruments/series-6400-picoammeters)** keithley.m
- **[OceanOptics spectrometer](https://www.oceaninsight.com/products/spectrometers/)** oceanoptics.m
- **[Physik Instruments piezo](https://www.physikinstrumente.co.uk/en/products/nanopositioning-piezo-flexure-stages/linear-piezo-flexure-stages/)** piezo_stage.m
- **[Thor Labs APT-based rotation stage](https://www.thorlabs.com/newgrouppage9.cfm?objectgroup_id=2875)** rotation_stage.m
- **[Thor Labs Kurios tunable bandpass filter](https://www.thorlabs.com/newgrouppage9.cfm?objectgroup_id=3488&pn=KURIOS-XL1/M)** kurios.m
- **[LabJack U-series](https://labjack.com/products/comparison-table)** labjack.m
- **[Stanford Instruments SR830 lock-in](https://www.thinksrs.com/products/sr810830.html)** SR830.m
- **[Thor Labs stepper motor](https://www.thorlabs.de/navigation.cfm?guide_id=2084)** stepper_motor.m
- **Thor Labs USB camera** thorcam.m
- **[LeCroy waverunner](https://teledynelecroy.com/oscilloscope/)** waverunner.m
- **[Thor Labs MLS203 microscope stage](https://www.thorlabs.com/thorproduct.cfm?partnumber=MLS203-1)** xy_controller.m
- **[Physik Instruments spii controller](https://acsmotioncontrol.com/)** spiiplus.m
- **[Zolix monochromators](http://www.zolix.com.cn/en/prodcon_370_376_741.html)** zolix.m

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

Please make sure to update tests as appropriate.

## License

Unless otherwise marked, these files are licensed under the [MIT](https://choosealicense.com/licenses/mit/).
