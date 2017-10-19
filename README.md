# Quantum Computer Simulator

This is a memory efficient simulator for a universal quantum computer.  It takes a program — a list of quantum gates and measurements — and computes one possible measurement outcome.

The calculations are based on the Feynmann path integral formulation of quantum mechanics and take exponential time in the number of Hadamard gates but only constant time in the number of qubits.

The software requires OS X El Capitan 10.11 or later because it uses [Apple's Metal compute API](https://developer.apple.com/metal/) to perform the highly parallel calculations on the GPU.

