import Foundation
import simd

/// Where the sun is directly overhead right now.
///
/// The real wallpaper shows the true terminator, so the light direction is
/// derived from the clock rather than parked at a flattering angle.
enum SolarPosition {

    /// Sub-solar latitude and longitude in degrees for a given instant.
    static func subsolarPoint(at date: Date = Date()) -> (latitude: Double, longitude: Double) {
        // days since the J2000.0 epoch (2000-01-01 12:00 UT)
        let j2000 = Date(timeIntervalSince1970: 946_728_000)
        let n = date.timeIntervalSince(j2000) / 86_400.0

        let rad = Double.pi / 180.0
        let meanLongitude = (280.460 + 0.985_647_4 * n).truncatingRemainder(dividingBy: 360)
        let meanAnomaly   = (357.528 + 0.985_600_3 * n).truncatingRemainder(dividingBy: 360)

        let eclipticLongitude = meanLongitude
            + 1.915 * sin(meanAnomaly * rad)
            + 0.020 * sin(2 * meanAnomaly * rad)
        let obliquity = 23.439 - 0.000_000_4 * n

        let declination = asin(sin(obliquity * rad) * sin(eclipticLongitude * rad)) / rad

        // equation of time, in minutes
        var rightAscension = atan2(cos(obliquity * rad) * sin(eclipticLongitude * rad),
                                   cos(eclipticLongitude * rad)) / rad
        rightAscension = rightAscension.truncatingRemainder(dividingBy: 360)
        var delta = meanLongitude - rightAscension
        if delta >  180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        let equationOfTime = 4 * delta

        var utcHours = date.timeIntervalSince1970 / 3600.0
        utcHours = utcHours.truncatingRemainder(dividingBy: 24)
        if utcHours < 0 { utcHours += 24 }

        var longitude = -15.0 * (utcHours + equationOfTime / 60.0 - 12.0)
        longitude = longitude.truncatingRemainder(dividingBy: 360)
        if longitude >  180 { longitude -= 360 }
        if longitude < -180 { longitude += 360 }

        return (declination, longitude)
    }

    /// Unit vector for a latitude/longitude in the world frame
    /// (+Y north, +Z toward 0° longitude).
    static func direction(latitude: Double, longitude: Double) -> SIMD3<Float> {
        let rad = Double.pi / 180.0
        let la = latitude * rad, lo = longitude * rad
        return SIMD3<Float>(Float(cos(la) * sin(lo)),
                            Float(sin(la)),
                            Float(cos(la) * cos(lo)))
    }

    /// Direction to the sun right now.
    static func sunDirection(at date: Date = Date()) -> SIMD3<Float> {
        let p = subsolarPoint(at: date)
        return direction(latitude: p.latitude, longitude: p.longitude)
    }
}
