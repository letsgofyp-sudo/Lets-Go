from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

from lets_go.utils import route_geometry


class TestRouteGeometry:
    def test_decode_polyline_empty(self):
        assert route_geometry._decode_ors_polyline('') == []

    def test_decode_polyline_known(self):
        dec = route_geometry._decode_ors_polyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@')
        assert dec[0] == pytest.approx((38.5, -120.2), abs=1e-5)

    @patch('lets_go.utils.route_geometry.api_key', '')
    def test_fetch_geometry_without_key(self):
        assert route_geometry.fetch_route_geometry_osm([(1, 2), (3, 4)]) == []

    @patch('lets_go.utils.route_geometry.api_key', 'abc')
    @patch('lets_go.utils.route_geometry.requests.post')
    def test_fetch_geometry_geojson(self, m_post):
        resp = MagicMock(status_code=200, text='ok')
        resp.raise_for_status.return_value = None
        resp.json.return_value = {'routes': [{'geometry': {'type': 'LineString', 'coordinates': [[1, 2], [3, 4]]}}]}
        m_post.return_value = resp
        out = route_geometry.fetch_route_geometry_osm([(2, 1), (4, 3)])
        assert out == [{'lat': 2.0, 'lng': 1.0}, {'lat': 4.0, 'lng': 3.0}]

    @patch('lets_go.utils.route_geometry.fetch_route_geometry_osm', return_value=[{'lat': 1.2, 'lng': 2.3}])
    @patch('lets_go.utils.route_geometry.RouteGeometryPoint.objects')
    @patch('lets_go.utils.route_geometry.RouteGeometryPoint')
    def test_update_route_geometry_from_stops(self, m_point_cls, m_objects, _m_fetch):
        route = SimpleNamespace(route_geometry=None, save=MagicMock())
        m_point_cls.side_effect = lambda **kwargs: kwargs
        route_geometry.update_route_geometry_from_stops(route, [{'lat': 1, 'lng': 2}, {'lat': 3, 'lng': 4}])
        route.save.assert_called_once()
        assert route.route_geometry == [{'lat': 1.2, 'lng': 2.3}]
        assert m_objects.bulk_create.called
