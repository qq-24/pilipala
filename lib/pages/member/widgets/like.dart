import 'package:flutter/material.dart';
import 'package:pilipala/common/constants.dart';
import 'package:pilipala/models/member/like.dart';
import 'package:pilipala/pages/member_like/widgets/item.dart';
import 'package:pilipala/utils/adaptive.dart';

class MemberLikePanel extends StatelessWidget {
  final List<MemberLikeDataModel> data;
  const MemberLikePanel({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, boxConstraints) {
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: responsiveCrossAxisCount(context),
            crossAxisSpacing: StyleString.safeSpace,
            mainAxisSpacing: StyleString.safeSpace,
            childAspectRatio: 0.94,
          ),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: data.length,
          itemBuilder: (context, i) {
            return MemberLikeItem(likeItem: data[i]);
          },
        );
      },
    );
  }
}
