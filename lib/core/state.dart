import 'package:ble_backend/work_state.dart';
import 'package:ble_ota/core/errors.dart';

class State extends WorkState<WorkStatus, Error> {
  State({
    super.status = WorkStatus.idle,
    super.error = Error.unknown,
  });
}
