/**
 * Mix 分队公共骨架（不编译，由 mt_elo / mt_rating 共享）
 *
 * 两个分队插件的差别只有两处：
 *   1. 强度分（score）从哪来：ELO 还是最近 N 场平均 RatingPro；
 *   2. 播报口径：数值保留几位小数、文案怎么写。
 * 采集参与名单、按分数排序、切成两队、落到队伍、播报名册这套逻辑完全一致，
 * 集中放在这里，避免两边算法各自演化后出现「同样的人算出不同分队」。
 * 分队本身是精确解：常规规模枚举所有分法取分差最小的一组，只有 survivor_limit
 * 被调得很大时才退化为蛇形分配 + 单交换优化。
 *
 * 约定：所有函数都以 client index 为键，分数放在长度为 MAXPLAYERS + 1 的数组里
 *       （即 score[client]），这样排序 / 交换只需要搬 client，不用搬结构体。
 *
 * 依赖：调用方必须先 #include <mix_team>（用 TEAM_SURVIVOR / SetClientTeam）
 *       和 #include <colors>（播报用 CPrintToChatAll）。
 */
#if defined _mt_balance_included_
 #endinput
#endif
#define _mt_balance_included_

/** 参与分队的最多玩家数（含 0 号槽位） */
#define MT_BALANCE_MAX_PLAYERS      (MAXPLAYERS + 1)

/** 交换优化的最大轮数，每轮最多做一次改进型交换 */
#define MT_BALANCE_MAX_SWAPS        256

/** 每队不超过这个人数时用精确枚举分队（C(20,10) = 184756 种分法，一次 mix 只算一遍） */
#define MT_BALANCE_EXACT_MAX_TEAM_SIZE  10

/** 单条聊天消息里名册部分的安全长度（字节），超出就换行继续播报 */
#define MT_BALANCE_ROSTER_CHUNK     110

/** 单个名册条目（名字 + 分数）的缓冲长度 */
#define MT_BALANCE_ENTRY_SIZE       128

/** 分数汇总 / 平均值等短文本的缓冲长度 */
#define MT_BALANCE_VALUE_SIZE       24

/** 一次分队的结果描述 */
enum struct MtSplit
{
	int size;       // 每队人数
	int leftover;   // 没分到队里、留在旁观的玩家数
	float diff;     // 两队总分差值（绝对值）
}

/**
 * 收集本次 mix 的参与者。
 *
 * @param clients       输出：client index 列表，长度至少为 maxClients
 * @param maxClients    输出缓冲能放多少个人
 * @return              实际收集到的人数
 */
stock int MtBalanceCollectMembers(int[] clients, int maxClients)
{
	int count = 0;

	for (int iClient = 1; iClient <= MaxClients && count < maxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient) || !IsMixMember(iClient)) {
			continue;
		}

		clients[count++] = iClient;
	}

	return count;
}

/**
 * 每队人数：人数对半分，但不越过 survivor_limit。
 * 多出来的人（人数为奇数 / 超出上限）留在旁观。
 *
 * @param count         参与总人数
 * @param maxPerTeam    单队上限（一般是 survivor_limit）
 * @return              每队人数，0 表示凑不出两队
 */
stock int MtBalanceResolveTeamSize(int count, int maxPerTeam)
{
	int teamSize = count / 2;

	if (teamSize > maxPerTeam) {
		teamSize = maxPerTeam;
	}

	return (teamSize < 0) ? 0 : teamSize;
}

/**
 * 按强度分从高到低排序（插入排序：人数很少，且稳定，同分不打乱原有顺序）。
 *
 * @param clients       待排序的 client 列表
 * @param count         列表长度
 * @param scores        强度分，scores[client]
 */
stock void MtBalanceSortDesc(int[] clients, int count, const float[] scores)
{
	for (int i = 1; i < count; i++)
	{
		int client = clients[i];
		int j = i - 1;

		while (j >= 0 && scores[clients[j]] < scores[client])
		{
			clients[j + 1] = clients[j];
			j--;
		}

		clients[j + 1] = client;
	}
}

/**
 * 一队的总分。
 */
stock float MtBalanceTeamSum(const int[] team, int size, const float[] scores)
{
	float total = 0.0;

	for (int i = 0; i < size; i++) {
		total += scores[team[i]];
	}

	return total;
}

/**
 * 组合枚举的下一步（字典序）：把 c[0..size-1] 推进到下一个「升序下标组合」。
 *
 * @param index         当前组合，内容必须严格升序
 * @param size          组合大小
 * @param count         下标上限（0 .. count-1）
 * @return              false = 已经是最后一个组合
 */
stock bool MtBalanceNextCombination(int[] index, int size, int count)
{
	int i = size - 1;

	while (i >= 0 && index[i] == count - size + i) {
		i--;
	}

	if (i < 0) {
		return false;
	}

	index[i]++;

	for (int j = i + 1; j < size; j++) {
		index[j] = index[j - 1] + 1;
	}

	return true;
}

/**
 * 精确分队：枚举所有「A 队拿哪 teamSize 个人」的组合，取两队总分差最小的一组。
 *
 * @return              最优分差
 */
stock float MtBalanceSplitExact(const int[] sorted, int teamSize, const float[] scores,
	int[] teamA, int[] teamB)
{
	int count = teamSize * 2;
	int index[MAXPLAYERS + 1];
	int best[MAXPLAYERS + 1];

	float total = 0.0;

	for (int i = 0; i < count; i++) {
		total += scores[sorted[i]];
	}

	bool bFound = false;
	float bestDiff = 0.0;

	for (int i = 0; i < teamSize; i++) {
		index[i] = i;
	}

	do
	{
		float sumA = 0.0;

		for (int i = 0; i < teamSize; i++) {
			sumA += scores[sorted[index[i]]];
		}

		float diff = FloatAbs(total - sumA * 2.0);

		if (!bFound || diff < bestDiff)
		{
			bFound = true;
			bestDiff = diff;

			for (int i = 0; i < teamSize; i++) {
				best[i] = index[i];
			}

			// 已经是理论最优（两边完全相等），不用再枚举了
			if (bestDiff < 0.001) {
				break;
			}
		}
	}
	while (MtBalanceNextCombination(index, teamSize, count));

	// 按下标还原两队：A 队是选中的那些人，B 队是剩下的
	int iTeamA = 0;
	int iTeamB = 0;
	int iBest = 0;

	for (int i = 0; i < count; i++)
	{
		if (iBest < teamSize && i == best[iBest])
		{
			teamA[iTeamA++] = sorted[i];
			iBest++;
		}

		else {
			teamB[iTeamB++] = sorted[i];
		}
	}

	return bestDiff;
}

/**
 * 蛇形分配：按实力从强到弱两两成对，第 0 对先 A 后 B，第 1 对先 B 后 A，以此类推。
 * 只在人数超出枚举范围时才作为初始分法使用。
 */
stock void MtBalanceSplitGreedy(const int[] sorted, int teamSize, int[] teamA, int[] teamB)
{
	for (int pair = 0; pair < teamSize; pair++)
	{
		int first = sorted[pair * 2];
		int second = sorted[pair * 2 + 1];

		if ((pair % 2) == 0) {
			teamA[pair] = first;
			teamB[pair] = second;
		}

		else {
			teamA[pair] = second;
			teamB[pair] = first;
		}
	}
}

/**
 * 在蛇形分法的基础上做单交换贪心优化：每次挑出让分差减少最多的一对互换，
 * 直到无法再改进（只接受严格变小，所以一定会收敛）。
 *
 * @return              交换后的两队总分差
 */
stock float MtBalanceImproveBySwap(int teamSize, const float[] scores, int[] teamA, int[] teamB)
{
	float sumA = MtBalanceTeamSum(teamA, teamSize, scores);
	float sumB = MtBalanceTeamSum(teamB, teamSize, scores);

	for (int round = 0; round < MT_BALANCE_MAX_SWAPS; round++)
	{
		float current = FloatAbs(sumA - sumB);
		float bestGain = 0.0;
		int bestA = -1;
		int bestB = -1;

		for (int i = 0; i < teamSize; i++)
		{
			for (int j = 0; j < teamSize; j++)
			{
				float delta = scores[teamB[j]] - scores[teamA[i]];
				float after = FloatAbs((sumA + delta) - (sumB - delta));
				float gain = current - after;

				if (gain > bestGain + 0.001)
				{
					bestGain = gain;
					bestA = i;
					bestB = j;
				}
			}
		}

		if (bestA < 0) {
			break;
		}

		float delta = scores[teamB[bestB]] - scores[teamA[bestA]];
		sumA += delta;
		sumB -= delta;

		int swap = teamA[bestA];
		teamA[bestA] = teamB[bestB];
		teamB[bestB] = swap;
	}

	return FloatAbs(sumA - sumB);
}

/**
 * 把排序后的名单切成两队，并让两队总分尽量接近。
 *
 * 常规规模（每队 ≤ MT_BALANCE_EXACT_MAX_TEAM_SIZE 人，覆盖 4v4 / 5v5 乃至 10v10）
 * 直接枚举所有分法，取分差最小的一组 —— 这是这个人数下能做到的最好结果
 * （C(20,10) = 184756 种，一次 mix 只算一遍）。
 * 只有 survivor_limit 被调得很大、枚举量会爆炸时，才退化为蛇形分法 + 交换优化。
 *
 * @param sorted        已按分数降序排好的 client 列表
 * @param count         列表长度
 * @param teamSize      每队人数（来自 MtBalanceResolveTeamSize）
 * @param scores        强度分，scores[client]
 * @param teamA         输出：A 队成员（人数 = teamSize）
 * @param teamB         输出：B 队成员（人数 = teamSize）
 * @param split         输出：分队结果描述（enum struct 本身按引用传递）
 */
stock void MtBalanceSplit(const int[] sorted, int count, int teamSize, const float[] scores,
	int[] teamA, int[] teamB, MtSplit split)
{
	split.size = teamSize;
	split.leftover = (count > teamSize * 2) ? (count - teamSize * 2) : 0;
	split.diff = 0.0;

	if (teamSize <= 0) {
		return;
	}

	if (teamSize <= MT_BALANCE_EXACT_MAX_TEAM_SIZE) {
		split.diff = MtBalanceSplitExact(sorted, teamSize, scores, teamA, teamB);
	}

	else
	{
		MtBalanceSplitGreedy(sorted, teamSize, teamA, teamB);
		split.diff = MtBalanceImproveBySwap(teamSize, scores, teamA, teamB);
	}

	// 播报要按分数从高到低念名字，枚举 / 交换后重新排一遍
	MtBalanceSortDesc(teamA, teamSize, scores);
	MtBalanceSortDesc(teamB, teamSize, scores);
}

/**
 * 精确分队（带队形权重）。
 *
 * 同时压两个目标：
 *   胜率平衡  |Δmean|     —— Elo 团队模型只吃均值，均值相等即 50%
 *   队形平衡  |σA − σB|   —— 压掉「一队 1 带 3、另一队四条平线」
 *
 * 目标函数：score = |Δmean| + shapeWeight × |σA − σB|
 * shapeWeight = 0 时等价于「只让两队总分差最小」。
 *
 * @return              选中的分队的两队总分差
 */
stock float MtBalanceSplitShape(const int[] sorted, int teamSize, const float[] scores,
	float shapeWeight, int[] teamA, int[] teamB)
{
	int count = teamSize * 2;
	int index[MAXPLAYERS + 1];
	int best[MAXPLAYERS + 1];

	float total = 0.0;
	float totalSq = 0.0;

	for (int i = 0; i < count; i++)
	{
		float value = scores[sorted[i]];
		total += value;
		totalSq += value * value;
	}

	bool bFound = false;
	float bestScore = 0.0;
	float bestDiff = 0.0;

	for (int i = 0; i < teamSize; i++) {
		index[i] = i;
	}

	do
	{
		float sumA = 0.0;
		float sqA = 0.0;

		for (int i = 0; i < teamSize; i++)
		{
			float value = scores[sorted[index[i]]];
			sumA += value;
			sqA += value * value;
		}

		float sumB = total - sumA;
		float sqB = totalSq - sqA;

		float meanA = sumA / float(teamSize);
		float meanB = sumB / float(teamSize);

		float varA = sqA / float(teamSize) - meanA * meanA;
		float varB = sqB / float(teamSize) - meanB * meanB;

		if (varA < 0.0) {
			varA = 0.0;
		}

		if (varB < 0.0) {
			varB = 0.0;
		}

		float dMean = FloatAbs(meanA - meanB);
		float dSpread = FloatAbs(SquareRoot(varA) - SquareRoot(varB));
		float score = dMean + shapeWeight * dSpread;
		float diff = FloatAbs(sumA - sumB);

		// 先比综合分，同分时再比总分差，保证结果稳定可复现
		if (!bFound || score < bestScore - 0.0001
			|| (FloatAbs(score - bestScore) <= 0.0001 && diff < bestDiff))
		{
			bFound = true;
			bestScore = score;
			bestDiff = diff;

			for (int i = 0; i < teamSize; i++) {
				best[i] = index[i];
			}

			// 综合分已经是 0（均值、队形都完全一致），继续枚举不会更好
			if (bestScore <= 0.0001) {
				break;
			}
		}
	}
	while (MtBalanceNextCombination(index, teamSize, count));

	int iTeamA = 0;
	int iTeamB = 0;
	int iBest = 0;

	for (int i = 0; i < count; i++)
	{
		if (iBest < teamSize && i == best[iBest])
		{
			teamA[iTeamA++] = sorted[i];
			iBest++;
		}

		else {
			teamB[iTeamB++] = sorted[i];
		}
	}

	return bestDiff;
}

/**
 * 带队形权重的分队入口：常规规模精确枚举，超出枚举上限时退回蛇形 + 交换优化。
 *
 * 与 MtBalanceSplit 的唯一区别是多一个 shapeWeight；MtBalanceSplit 保持原行为，
 * 供 mt_rating 等「只按分数接近」的类型继续使用。
 */
stock void MtBalanceSplitWeighted(const int[] sorted, int count, int teamSize, const float[] scores,
	int[] teamA, int[] teamB, MtSplit split, float shapeWeight)
{
	split.size = teamSize;
	split.leftover = (count > teamSize * 2) ? (count - teamSize * 2) : 0;
	split.diff = 0.0;

	if (teamSize <= 0) {
		return;
	}

	if (teamSize <= MT_BALANCE_EXACT_MAX_TEAM_SIZE) {
		split.diff = MtBalanceSplitShape(sorted, teamSize, scores, shapeWeight, teamA, teamB);
	}

	else {
		MtBalanceSplitGreedy(sorted, teamSize, teamA, teamB);
		split.diff = MtBalanceImproveBySwap(teamSize, scores, teamA, teamB);
	}

	MtBalanceSortDesc(teamA, teamSize, scores);
	MtBalanceSortDesc(teamB, teamSize, scores);
}

/**
 * 把两队玩家真正放进游戏里的队伍。
 *
 * 顺序有讲究：生还者要靠接管 survivor bot 才能落位，所以必须先处理其它队伍，
 * 否则提前占满 bot 会导致生还者落位失败。
 *
 * @param teamA         A 队成员
 * @param sizeA         A 队人数
 * @param teamB         B 队成员
 * @param sizeB         B 队人数
 * @param teamAId       A 队目标队伍（TEAM_SURVIVOR / TEAM_INFECTED）
 * @param teamBId       B 队目标队伍
 * @return              true = 所有人都已落位
 */
stock bool MtBalanceApply(const int[] teamA, int sizeA, const int[] teamB, int sizeB, int teamAId, int teamBId)
{
	if (teamAId == TEAM_SURVIVOR) {
		return MtBalanceApplyTeam(teamB, sizeB, teamBId) && MtBalanceApplyTeam(teamA, sizeA, teamAId);
	}

	return MtBalanceApplyTeam(teamA, sizeA, teamAId) && MtBalanceApplyTeam(teamB, sizeB, teamBId);
}

/**
 * 把一队人放进同一个队伍，任何一个失败就整体返回 false（调用方负责回滚）。
 */
stock bool MtBalanceApplyTeam(const int[] team, int size, int teamId)
{
	for (int i = 0; i < size; i++)
	{
		if (!SetClientTeam(team[i], teamId))
		{
			LogError("[MixBalance] 无法把玩家 %d 放进队伍 %d，已放弃本次分队", team[i], teamId);
			return false;
		}
	}

	return true;
}

/**
 * 播报一队的名册：合计分 / 平均分 + 每个玩家的分数。
 *
 * 聊天消息长度有限（约 190 字节），中文名字一个字占 3 字节，人多时会自动拆成
 * 多条消息，后续几条用 morePhrase 开头。
 *
 * @param firstPhrase   该队第一条消息的翻译键
 * @param morePhrase    该队续行消息的翻译键
 * @param team          该队成员（client index）
 * @param size          该队人数
 * @param scores        强度分，scores[client]
 * @param fallback      该玩家是否用了缺省值，true 时名字后面标 *
 * @param decimals      分数保留几位小数（0 = ELO 这类整数）
 */
stock void MtBalancePrintTeam(const char[] firstPhrase, const char[] morePhrase, const int[] team, int size,
	const float[] scores, const bool[] fallback, int decimals)
{
	if (size <= 0) {
		return;
	}

	float total = 0.0;

	for (int i = 0; i < size; i++) {
		total += scores[team[i]];
	}

	char sTotal[MT_BALANCE_VALUE_SIZE];
	char sAverage[MT_BALANCE_VALUE_SIZE];

	if (decimals > 0) {
		Format(sTotal, sizeof(sTotal), "%.2f", total);
		Format(sAverage, sizeof(sAverage), "%.2f", total / float(size));
	}

	else {
		Format(sTotal, sizeof(sTotal), "%.0f", total);
		Format(sAverage, sizeof(sAverage), "%.0f", total / float(size));
	}

	char sRoster[MT_BALANCE_ROSTER_CHUNK * 2] = "";
	bool bFirstChunk = true;

	for (int i = 0; i < size; i++)
	{
		char sEntry[MT_BALANCE_ENTRY_SIZE];
		MtBalanceFormatEntry(sEntry, sizeof(sEntry), team[i], scores[team[i]], fallback[team[i]], decimals);

		if (sRoster[0] != '\0' && (strlen(sRoster) + strlen(sEntry) + 4) > MT_BALANCE_ROSTER_CHUNK)
		{
			MtBalancePrintRoster(bFirstChunk ? firstPhrase : morePhrase, sTotal, sAverage, sRoster);
			bFirstChunk = false;
			sRoster[0] = '\0';
		}

		if (sRoster[0] != '\0') {
			StrCat(sRoster, sizeof(sRoster), " ");
		}

		StrCat(sRoster, sizeof(sRoster), sEntry);
	}

	if (sRoster[0] != '\0') {
		MtBalancePrintRoster(bFirstChunk ? firstPhrase : morePhrase, sTotal, sAverage, sRoster);
	}
}

/**
 * 发出一条名册播报。单独包一层是为了把「翻译键」当字符串参数显式传进去，
 * 不依赖三元表达式直接进可变参数列表。
 */
stock void MtBalancePrintRoster(const char[] sPhrase, const char[] sTotal, const char[] sAverage, const char[] sRoster)
{
	CPrintToChatAll("%t", sPhrase, sTotal, sAverage, sRoster);
}

/**
 * 格式化单个名册条目：名字(分数) 或 名字(分数*)。
 */
stock void MtBalanceFormatEntry(char[] sEntry, int maxlen, int client, float score, bool fallback, int decimals)
{
	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));

	// 带 * 表示这个分数是缺数据时补的默认值，播报里会单独说明
	if (decimals > 0) {
		Format(sEntry, maxlen, fallback ? "%s(%.2f*)" : "%s(%.2f)", sName, score);
	}

	else {
		Format(sEntry, maxlen, fallback ? "%s(%.0f*)" : "%s(%.0f)", sName, score);
	}
}
