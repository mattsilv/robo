import Testing
import simd
@testable import Robo

// MARK: - Polygon Area (Shoelace Formula)

@Test func polygonAreaSquare10x10() {
    let corners: [simd_float3] = [
        simd_float3(0, 0, 0),
        simd_float3(10, 0, 0),
        simd_float3(10, 0, 10),
        simd_float3(0, 0, 10)
    ]
    let area = RoomDataProcessor.polygonArea(corners)
    #expect(abs(area - 100.0) < 0.01)
}

@Test func polygonAreaRectangle3x4() {
    let corners: [simd_float3] = [
        simd_float3(0, 0, 0),
        simd_float3(3, 0, 0),
        simd_float3(3, 0, 4),
        simd_float3(0, 0, 4)
    ]
    let area = RoomDataProcessor.polygonArea(corners)
    #expect(abs(area - 12.0) < 0.01)
}

@Test func polygonAreaTriangle() {
    // Right triangle with legs 3 and 4 = area 6
    let corners: [simd_float3] = [
        simd_float3(0, 0, 0),
        simd_float3(3, 0, 0),
        simd_float3(0, 0, 4)
    ]
    let area = RoomDataProcessor.polygonArea(corners)
    #expect(abs(area - 6.0) < 0.01)
}

@Test func polygonAreaLShaped() {
    // L-shape: 10x10 square minus 5x5 corner = 75 sqm
    let corners: [simd_float3] = [
        simd_float3(0, 0, 0),
        simd_float3(10, 0, 0),
        simd_float3(10, 0, 5),
        simd_float3(5, 0, 5),
        simd_float3(5, 0, 10),
        simd_float3(0, 0, 10)
    ]
    let area = RoomDataProcessor.polygonArea(corners)
    #expect(abs(area - 75.0) < 0.01)
}

@Test func polygonAreaWithNonZeroYCoordinates() {
    // Y coordinate should be ignored (it's vertical height)
    let corners: [simd_float3] = [
        simd_float3(0, 1.5, 0),
        simd_float3(5, 1.5, 0),
        simd_float3(5, 1.5, 4),
        simd_float3(0, 1.5, 4)
    ]
    let area = RoomDataProcessor.polygonArea(corners)
    #expect(abs(area - 20.0) < 0.01)
}

@Test func polygonAreaTwoPointsReturnsZero() {
    let corners: [simd_float3] = [
        simd_float3(0, 0, 0),
        simd_float3(5, 0, 0)
    ]
    let area = RoomDataProcessor.polygonArea(corners)
    #expect(area == 0.0)
}

@Test func polygonAreaEmptyReturnsZero() {
    let area = RoomDataProcessor.polygonArea([])
    #expect(area == 0.0)
}

// MARK: - Bounding Box Dimensions

@Test func boundingBoxSimpleRectangle() {
    // 4 wall positions forming a rectangle
    let positions: [(x: Double, z: Double)] = [
        (x: 0, z: 0),
        (x: 5, z: 0),
        (x: 5, z: 3),
        (x: 0, z: 3)
    ]
    let dims = RoomDataProcessor.boundingBoxDimensions(positions)
    #expect(dims != nil)
    #expect(abs(dims!.length - 5.0) < 0.01)
    #expect(abs(dims!.width - 3.0) < 0.01)
}

@Test func boundingBoxTooFewPositionsReturnsNil() {
    let positions: [(x: Double, z: Double)] = [
        (x: 0, z: 0),
        (x: 5, z: 0)
    ]
    let dims = RoomDataProcessor.boundingBoxDimensions(positions)
    #expect(dims == nil)
}

@Test func boundingBoxLengthAlwaysGreaterOrEqualToWidth() {
    let positions: [(x: Double, z: Double)] = [
        (x: 0, z: 0),
        (x: 2, z: 0),
        (x: 2, z: 8),
        (x: 0, z: 8)
    ]
    let dims = RoomDataProcessor.boundingBoxDimensions(positions)
    #expect(dims != nil)
    #expect(dims!.length >= dims!.width)
    #expect(abs(dims!.length - 8.0) < 0.01)
    #expect(abs(dims!.width - 2.0) < 0.01)
}

// MARK: - Perimeter Square Area

@Test func perimeterSquareAreaFourEqualWalls() {
    // 4 walls of 5m each = 20m perimeter, side = 5m, area = 25 sqm
    let widths = [5.0, 5.0, 5.0, 5.0]
    let area = RoomDataProcessor.perimeterSquareArea(widths)
    #expect(abs(area - 25.0) < 0.01)
}

@Test func perimeterSquareAreaUnequalWalls() {
    // Perimeter = 3+7+3+7 = 20m, side = 5m, area = 25 sqm
    let widths = [3.0, 7.0, 3.0, 7.0]
    let area = RoomDataProcessor.perimeterSquareArea(widths)
    #expect(abs(area - 25.0) < 0.01)
}

@Test func perimeterSquareAreaEmptyReturnsZero() {
    let area = RoomDataProcessor.perimeterSquareArea([])
    #expect(area == 0.0)
}

// MARK: - Conversion Constants

@Test func metersToFeetConversion() {
    #expect(abs(RoomDataProcessor.metersToFeet - 3.28084) < 0.0001)
}

@Test func sqmToSqftConversion() {
    // 1 sqm = 10.7639 sqft
    let sqm = 100.0
    let sqft = sqm * RoomDataProcessor.sqmToSqft
    #expect(abs(sqft - 1076.39) < 0.01)
}
