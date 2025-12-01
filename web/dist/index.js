// web/dist/index.js - Extend provided React for passengers
// Add passenger UI component similar to distance/speed
const PassengerUI = () => {
    const { passengers } = useTrainState();
    return <div>Passengers: {passengers}</div>;
};
// Integrate into main render