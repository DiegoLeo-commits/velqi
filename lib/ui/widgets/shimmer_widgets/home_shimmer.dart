import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'basic_container.dart';

class HomeShimmer extends StatelessWidget {
  const HomeShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
        baseColor: Colors.grey[500]!,
        highlightColor: Colors.grey[300]!,
        enabled: true,
        direction: ShimmerDirection.ltr,
        child: Column(
          children: [_discoverWidget(), _contentWidget(), _contentWidget()],
        ));
  }

  Widget _discoverWidget() {
    return SizedBox(
      height: 290,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: BasicShimmerContainer(Size(180, 24)),
          ),
          Expanded(
            child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 4, right: 16),
                itemCount: 4,
                itemBuilder: (_, item) {
                  return Container(
                    width: 320,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 90,
                            height: 90,
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const BasicShimmerContainer(Size(120, 16)),
                              const SizedBox(height: 8),
                              const BasicShimmerContainer(Size(80, 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
          ),
        ],
      ),
    );
  }

  Widget _contentWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: BasicShimmerContainer(Size(200, 24)),
        ),
        SizedBox(
          height: 210,
          child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 4, right: 16),
              itemCount: 5,
              itemBuilder: (_, index) {
                return Container(
                  width: 130,
                  margin: const EdgeInsets.only(right: 12),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                        child: BasicShimmerContainer(Size(130, 130)),
                      ),
                      SizedBox(height: 8),
                      BasicShimmerContainer(Size(110, 14)),
                      SizedBox(height: 4),
                      BasicShimmerContainer(Size(70, 11)),
                    ],
                  ),
                );
              }),
        ),
      ],
    );
  }
}
