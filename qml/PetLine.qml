import QtQuick
import QtQuick.Shapes

// A stroked SVG path without fill (the page's .st .st-cl .st-m and whiskers).
ShapePath {
    id: part
    property string d
    property color color: "transparent"
    property real width: 1
    fillColor: "transparent"
    strokeColor: color
    strokeWidth: width
    joinStyle: ShapePath.RoundJoin
    capStyle: ShapePath.RoundCap
    PathSvg { path: part.d }
}
