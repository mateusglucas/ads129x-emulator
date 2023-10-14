# ADS129x Emulator

A VHDL component to emulate daisy-chained associations of [ADS1298](https://www.ti.com/product/ADS1298)/[ADS1299](https://www.ti.com/product/ADS1299) in continuous conversion mode.

During the development of systems that use multiple daisy-chained ADS129x devices, it is necessary to access the system performance during signal acquisition in order to garantee that the system design will meet the timing and throughput requirements of this critical stage.

This component is intended to allow proofs of concept of the design in the signal acquisition stage without the need for any ADS129x, potencially reducing the costs of the prototyping phase.
